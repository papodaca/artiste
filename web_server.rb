#!/usr/bin/env ruby

require 'sinatra/base'
require 'pathname'
require 'base64'
require_relative 'config/environment'
require_relative 'config/database'

class PhotoGalleryApp < Sinatra::Base
  # Set up the web server
  set :port, 4567
  set :bind, '0.0.0.0'

  configure do
    set :threaded, false
  end

  # Helper method to get all photos recursively from db/photos
  def get_photos
    photos_dir = File.join(settings.root, 'db', 'photos')
    return [] unless Dir.exist?(photos_dir)
    
    # Find all image files recursively
    photo_extensions = %w[.jpg .jpeg .png .gif .bmp .webp]
    photos = []
    
    Dir.glob(File.join(photos_dir, '**', '*')).each do |file|
      next unless File.file?(file)
      ext = File.extname(file).downcase
      next unless photo_extensions.include?(ext)
      
      # Get relative path from photos directory
      relative_path = Pathname.new(file).relative_path_from(Pathname.new(photos_dir))
      photos << relative_path.to_s
    end
    
    # Sort alphabetically
    photos.sort
  end

  # Root route - display photos
  get '/' do
    @photos = get_photos
    erb :index
  end

  # Details route - show generation task details for a photo
  get '/details/*' do
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
  get '/photo/*' do
    photo_path = params[:splat][0]
    full_path = File.join(settings.root, 'db', 'photos', photo_path)
    
    # Security check - ensure the path is within db/photos
    photos_dir = File.realpath(File.join(settings.root, 'db', 'photos'))
    requested_path = File.realpath(full_path) rescue nil
    
    if requested_path.nil? || !requested_path.start_with?(photos_dir) || !File.exist?(requested_path)
      status 404
      return "Photo not found"
    end
    
    # Determine content type based on file extension
    content_type = case File.extname(requested_path).downcase
    when '.jpg', '.jpeg' then 'image/jpeg'
    when '.png' then 'image/png'
    when '.gif' then 'image/gif'
    when '.bmp' then 'image/bmp'
    when '.webp' then 'image/webp'
    else 'application/octet-stream'
    end
    
    headers 'Content-Type' => content_type
    File.read(requested_path)
  end
end
