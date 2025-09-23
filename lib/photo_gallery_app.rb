#!/usr/bin/env ruby

require "sinatra/base"
require "pathname"
require "base64"
require_relative "openai_api"

class PhotoGalleryApp < Sinatra::Base
  # Set up the web server
  set :port, 4567
  set :bind, "0.0.0.0"

  attr_reader :photos_path

  # Default batch size for infinite scrolling
  PHOTO_BATCH_SIZE = 20

  def initialize(photos_path = File.join(settings.root, "..", "db", "photos"), debug_mode = false)
    @photos_path = photos_path
    @debug_mode = debug_mode
    super()
    # Only start WebSocket server if not in test environment
    start_websocket_server unless ENV["RACK_ENV"] == "test"
  end

  configure do
    set :threaded, false

    set :host_authorization, {permitted_hosts: []}
  end

  def start_websocket_server
    # Start WebSocket server in a separate thread
    Thread.new do
      PhotoGalleryWebSocket.start_server(host: "0.0.0.0", port: 4568)
    rescue => e
      puts "Failed to start WebSocket server: #{e.message}"
      puts e.backtrace.join("\n")
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
    # Check if we're in debug mode (which includes --dev flag)
    if @debug_mode
      # In dev mode, redirect to the Vite dev server
      redirect to("http://localhost:5173")
    else
      # In production mode, serve the built Svelte app
      send_file File.join(settings.root, "..", "frontend", "dist", "index.html")
    end
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

  # Helper method to check if IP is in allowed ranges
  def ip_allowed?(ip)
    # Allow localhost
    return true if ip == "127.0.0.1" || ip == "::1"

    # Check if IP is within the configured CIDR range
    cidr_range = ENV["ARTISTE_BROADCAST_CIDR"]
    return false unless cidr_range

    begin
      # Parse CIDR notation (e.g., "172.31.0.0/16")
      network_str, prefix_str = cidr_range.split("/")
      prefix = prefix_str.to_i

      # Convert IP and network to integer representation
      ip_int = ip_to_int(ip)
      network_int = ip_to_int(network_str)

      # Calculate network mask
      mask = (0xffffffff << (32 - prefix)) & 0xffffffff

      # Check if IP is in the network range
      (ip_int & mask) == (network_int & mask)
    rescue => e
      puts "Error parsing CIDR range #{cidr_range}: #{e.message}"
      false
    end
  end

  def ip_to_int(ip)
    if ip.include?(".")
      ip.split(".").map(&:to_i).pack("C*").unpack1("N")
    else
      0
    end
  end

  def client_ip
    if (forwarded_for = request.env["HTTP_X_FORWARDED_FOR"])
      forwarded_for.split(",").first.strip
    else
      request.ip
    end
  end

  post "/api/broadcast" do
    content_type :json

    unless ip_allowed?(client_ip)
      status 403
      return {message: "Access denied."}.to_json
    end

    begin
      # Parse the JSON request body
      request_body = JSON.parse(request.body.read)

      PhotoGalleryWebSocket.local_broadcast(request_body)

      {status: "ok", message: "Broadcast successful"}.to_json
    rescue JSON::ParserError
      status 400
      {error: "Invalid JSON"}.to_json
    rescue => e
      puts "Error processing broadcast: #{e.message}"
      status 500
      {error: "Internal server error"}.to_json
    end
  end

  # Register the OpenAI API middleware
  use OpenAIAPI
end
