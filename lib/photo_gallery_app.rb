#!/usr/bin/env ruby

require "sinatra/base"
require "pathname"
require "base64"
require_relative "photo_gallery_websocket"

class PhotoGalleryApp < Sinatra::Base
  # Set up the web server
  set :port, 4567
  set :bind, "0.0.0.0"

  attr_reader :photos_path

  # Default batch size for infinite scrolling
  PHOTO_BATCH_SIZE = 20

  def initialize(photos_path = File.join(settings.root, "..", "db", "photos"))
    @photos_path = photos_path
    super()
    # Only start WebSocket server if not in test environment
    start_websocket_server unless ENV['RACK_ENV'] == 'test'
  end

  configure do
    set :threaded, false

    # Allow hosts from ALLOWED_HOSTS env var
    allowed_hosts = ENV["ALLOWED_HOSTS"]&.split(",")&.map(&:strip) || ["localhost", "127.0.0.1"]

    set :host_authorization, {
      permitted_hosts: allowed_hosts
    }
  end

  def start_websocket_server
    # Start WebSocket server in a separate thread
    Thread.new do
      begin
        PhotoGalleryWebSocket.start_server(host: "0.0.0.0", port: 4568)
      rescue => e
        puts "Failed to start WebSocket server: #{e.message}"
        puts e.backtrace.join("\n")
      end
    end
    sleep 0.1 # Give the thread a moment to start
  end

  # Helper method to get all completed photos from the database
  def get_photos(offset: 0, limit: nil)
    # Get all completed generation tasks, ordered by completed_at in descending order (newest first)
    tasks = GenerationTask.pub.reverse_order(:completed_at)

    # Build photo paths from task data
    photos = tasks.map do |task|
      # Construct the relative path from photos directory
      # file_path returns the directory path like "db/photos/YYYY/MM/DD"
      dir = task.file_path
      # Remove the "db/photos/" prefix to get just YYYY/MM/DD
      date_path = dir.gsub(/^db\/photos\//, "")
      # Combine with output filename
      File.join(date_path, task.output_filename) if task.output_filename
    end.compact # Remove any nil entries

    # Apply pagination if specified
    if limit
      photos[offset, limit] || []
    else
      # If no limit, return all photos starting from offset
      photos.drop(offset)
    end
  end

  # Root route - serve Svelte frontend
  get "/" do
    send_file File.join(settings.root, "..", "frontend", "dist", "index.html")
  end

  # Serve vite.svg file
  get "/gallery.svg" do
    file_path = File.join(settings.root, "..", "frontend", "dist", "gallery.svg")

    # Check if file exists
    if !File.exist?(file_path)
      status 404
      return "File not found"
    end

    headers "Content-Type" => "image/svg+xml"
    File.read(file_path)
  end

  # Serve static files from Svelte build
  get "/assets/*" do
    asset_path = params[:splat][0]
    file_path = File.join(settings.root, "..", "frontend", "dist", "assets", asset_path)

    # Security check - ensure the path is within the assets directory
    assets_dir = File.join(settings.root, "..", "frontend", "dist", "assets")
    requested_path = file_path

    # Check if file exists and is within the assets directory
    if !File.exist?(requested_path) || !requested_path.start_with?(assets_dir)
      status 404
      return "File not found"
    end

    # Determine content type based on file extension
    content_type = case File.extname(requested_path).downcase
    when ".js" then "application/javascript"
    when ".css" then "text/css"
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".svg" then "image/svg+xml"
    when ".map" then "application/json"
    else "application/octet-stream"
    end

    headers "Content-Type" => content_type
    File.read(requested_path)
  end

  # API endpoint for infinite scroll - returns JSON list of photos
  get "/api/photos" do
    content_type :json

    # Parse offset and limit parameters
    offset = params[:offset].to_i if params[:offset]
    offset ||= 0
    limit = params[:limit].to_i if params[:limit]
    limit = limit.between?(1, 100) ? limit : PHOTO_BATCH_SIZE # Cap limit at 100

    # Get photos with pagination
    photos = get_photos(offset: offset, limit: limit)

    # Return as JSON
    {photos: photos}.to_json
  end

  # API endpoint for photo details
  get "/api/photo-details/*" do
    content_type :json

    begin
      photo_path = params[:splat][0]
      filename = File.basename(photo_path)

      # Find the generation task by filename
      task = GenerationTask.where(output_filename: filename).first

      if task.nil?
        status 404
        return {error: "Generation task not found for #{filename}"}.to_json
      end

      # Safely parse parameters JSON
      parameters = {}
      if task.parameters && !task.parameters.empty? && task.parameters != "{}"
        begin
          parameters = JSON.parse(task.parameters)
        rescue JSON::ParserError
          # If JSON parsing fails, just return empty hash
          parameters = {}
        end
      end

      # Safely parse EXIF data JSON
      exif_data = {}
      if task.exif_data && !task.exif_data.empty? && task.exif_data != "{}"
        begin
          exif_data = JSON.parse(task.exif_data)
        rescue JSON::ParserError
          # If JSON parsing fails, just return empty hash
          exif_data = {}
        end
      end

      # Return photo details as JSON
      {
        photo_path: photo_path,
        task: {
          output_filename: task.output_filename,
          status: task.status,
          username: task.username || task.user_id,
          workflow_type: task.workflow_type || "Unknown",
          queued_at: task.queued_at ? task.queued_at.strftime("%Y-%m-%d %H:%M:%S") : nil,
          started_at: task.started_at ? task.started_at.strftime("%Y-%m-%d %H:%M:%S") : nil,
          completed_at: task.completed_at ? task.completed_at.strftime("%Y-%m-%d %H:%M:%S") : nil,
          processing_time_seconds: task.processing_time_seconds,
          prompt: task.prompt,
          parameters: parameters,
          exif_data: exif_data,
          error_message: task.error_message,
          comfyui_prompt_id: task.comfyui_prompt_id
        }
      }.to_json
    rescue => e
      # Log the error for debugging
      puts "Error in /api/photo-details/: #{e.class.name}: #{e.message}"
      puts e.backtrace.join("\n")

      status 500
      return {error: "Internal server error: #{e.class.name}: #{e.message}"}.to_json
    end
  end

  # Route to serve individual photos
  get "/photo/*" do
    photo_path = params[:splat][0]
    full_path = File.join(photos_path, photo_path)

    # Security check - ensure the path is within db/photos
    photos_dir = File.realpath(photos_path)
    requested_path = begin
      File.realpath(full_path)
    rescue
      nil
    end

    if requested_path.nil? || !requested_path.start_with?(photos_dir) || !File.exist?(requested_path)
      status 404
      return "Photo not found"
    end

    # Determine content type based on file extension
    content_type = case File.extname(requested_path).downcase
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".png" then "image/png"
    when ".gif" then "image/gif"
    when ".bmp" then "image/bmp"
    when ".webp" then "image/webp"
    else "application/octet-stream"
    end

    headers "Content-Type" => content_type
    File.read(requested_path)
  end
end
