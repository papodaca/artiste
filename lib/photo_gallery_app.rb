#!/usr/bin/env ruby

require "sinatra/base"
require "pathname"
require "base64"

class PhotoGalleryApp < Sinatra::Base
  # Set up the web server
  set :port, 4567
  set :bind, "0.0.0.0"

  attr_reader :photos_path

  def initialize(photos_path = File.join(settings.root, "..", "db", "photos"))
    @photos_path = photos_path
    super()
  end

  configure do
    set :threaded, false

    # Allow hosts from ALLOWED_HOSTS env var
    allowed_hosts = ENV["ALLOWED_HOSTS"]&.split(",")&.map(&:strip) || ["localhost", "127.0.0.1"]

    set :host_authorization, {
      permitted_hosts: allowed_hosts
    }
  end

  # Helper method to get all photos recursively from db/photos
  def get_photos
    return [] unless Dir.exist?(photos_path)

    # Find all image files recursively
    photo_extensions = %w[.jpg .jpeg .png .gif .bmp .webp]
    photos = []

    Dir.glob(File.join(photos_path, "**", "*")).each do |file|
      next unless File.file?(file)
      ext = File.extname(file).downcase
      next unless photo_extensions.include?(ext)

      # Get relative path from photos directory
      relative_path = Pathname.new(file).relative_path_from(Pathname.new(photos_path))
      photos << relative_path.to_s
    end

    # Sort alphabetically
    photos.sort
  end

  # Root route - display photos
  get "/" do
    @photos = get_photos
    erb :index
  end

  # Details route - show generation task details for a photo
  get "/details/*" do
    photo_path = params[:splat][0]
    filename = File.basename(photo_path)

    # Find the generation task by filename
    @task = GenerationTask.where(output_filename: filename).first

    if @task.nil?
      status 404
      return "Generation task not found for #{filename}"
    end

    @photo_path = photo_path
    erb :details
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
