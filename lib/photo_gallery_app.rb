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
    set :views, File.join(settings.root, "..", "views")
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

    # Build photo data from task data
    photos = tasks.map do |task|
      # Construct the relative path from photos directory
      # file_path returns the directory path like "db/photos/YYYY/MM/DD"
      dir = task.file_path
      # Remove the "db/photos/" prefix to get just YYYY/MM/DD
      date_path = dir.gsub(/^db\/photos\//, "")
      # Combine with output filename
      if task.output_filename
        {
          path: File.join(date_path, task.output_filename),
          id: task.id
        }
      end
    end.compact # Remove any nil entries

    # Apply pagination if specified
    if limit
      photos[offset, limit] || []
    else
      # If no limit, return all photos starting from offset
      photos.drop(offset)
    end
  end

  # Helper methods for ERB templates
  def get_filename(path)
    path.split("/").last
  end

  def is_video(path)
    path.downcase.end_with?(".mp4")
  end

  def get_status_class(status)
    case status
    when "completed"
      "bg-status-completed-bg text-status-completed-text"
    when "processing"
      "bg-status-processing-bg text-status-processing-text"
    when "failed"
      "bg-status-failed-bg text-status-failed-text"
    else
      "bg-status-pending-bg text-status-pending-text"
    end
  end

  def format_date(date_string)
    return "N/A" unless date_string
    begin
      date = Date.parse(date_string)
      date.strftime("%B %d, %Y at %I:%M %p")
    rescue
      date_string
    end
  end

  def format_processing_time(seconds)
    return "N/A" unless seconds

    ActiveSupport::Duration.build(seconds).parts.map do |key, value|
      [value.to_i, key].join(" ")
    end.join(" ")
  end

  def format_json(obj)
    return "" unless obj && !obj.empty?
    JSON.pretty_generate(obj)
  rescue
    obj.to_s
  end

  def escape_html(text)
    CGI.escapeHTML(text.to_s)
  end

  get "/" do
    offset = 0
    limit = PHOTO_BATCH_SIZE
    photos = get_photos(offset:, limit:)
    photo_details = params.has_key?(:detail) ? get_photo_details(params[:detail]) : nil

    # Handle presets parameter
    if params.has_key?(:presets)
      begin
        @presets = Preset.order(:name).all
        @presets_error = nil
      rescue => e
        @presets = nil
        @presets_error = "Error loading presets: #{e.message}"
      end
    end

    erb :gallery, layout: :layout, locals: {photos:, offset:, limit:, photo_details:}
  end

  get "/tasks" do
    redirect to("/") unless request.env["HTTP_ACCEPT"]&.include?("text/vnd.turbo-stream.html")

    offset = params[:offset].to_i if params[:offset]
    offset ||= 0
    limit = params[:limit].to_i if params[:limit]
    limit = limit.between?(1, 100) ? limit : PHOTO_BATCH_SIZE
    photos = get_photos(offset: offset, limit: limit)
    has_more = photos.length == limit

    content_type "text/vnd.turbo-stream.html"
    erb :photo_stream, layout: nil, locals: {photos:, offset:, limit:, has_more:}
  end
  # Photo details route for Turbo Frame modal
  get "/photo-details/:id" do
    content_type :html

    begin
      redirect to("/?detail=#{params[:id]}") unless request.env["HTTP_TURBO_FRAME"].present?

      photo_details = get_photo_details(params[:id])
      if photo_details.has_key?(:error)
        return erb :photo_details, layout: false, locals: {photo_details: nil, error: photo_details[:error]}
      end

      erb :photo_details, layout: false, locals: {photo_details: photo_details, error: nil}
    rescue => e
      # Log the error for debugging
      puts "Error in /photo-details/: #{e.class.name}: #{e.message}"
      puts e.backtrace.join("\n")

      error = "Internal server error: #{e.class.name}: #{e.message}"
      erb :photo_details, layout: false, locals: {photo_details: nil, error: error}
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

  def get_photo_details(id)
    task = GenerationTask[id.to_i]

    if task.nil?
      return {error: "Generation task not found for ID #{id}"}
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

    # Construct the photo path
    dir = task.file_path
    date_path = dir.gsub(/^db\/photos\//, "")
    photo_path = File.join(date_path, task.output_filename) if task.output_filename

    return {
      photo_path: photo_path,
      task: {
        id: task.id,
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
        prompt_id: task.prompt_id
      }
    }
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

  # Presets modal route
  get "/presets" do
    content_type :html

    begin
      presets = Preset.order(:name).all

      redirect to("/?presets=true") unless request.env["HTTP_TURBO_FRAME"].present?

      erb :presets_details, layout: false, locals: {presets: presets, error: nil}
    rescue => e
      # Log the error for debugging
      puts "Error in /presets: #{e.class.name}: #{e.message}"
      puts e.backtrace.join("\n")

      error = "Internal server error: #{e.class.name}: #{e.message}"
      erb :presets_details, layout: false, locals: {presets: nil, error: error}
    end
  end

  # Register the OpenAI API middleware
  use OpenAiApi
end
