require "json"
require "securerandom"

class OpenAIAPI < Sinatra::Base
  configure do
    set :threaded, false

    set :host_authorization, {permitted_hosts: []}
  end
  # OpenAI-compatible API endpoint for image generation
  post "/images/generations" do
    content_type :json

    # Check for Authorization header
    auth_header = request.env["HTTP_AUTHORIZATION"]
    unless auth_header&.start_with?("Bearer ")
      status 401
      return {error: "Authentication required. Please provide a valid Bearer token."}.to_json
    end

    # Extract and validate token
    token = auth_header.sub(/^Bearer /, "").strip
    api_token = ENV["API_TOKEN"]

    unless api_token
      status 500
      return {error: "API_TOKEN environment variable is not configured on the server."}.to_json
    end

    unless token == api_token
      status 401
      return {error: "Invalid authentication token."}.to_json
    end

    begin
      # Parse the JSON request body
      request_body = JSON.parse(request.body.read)

      if request_body["stream"].is_a?(TrueClass)
        status 400
        return {error: "Streaming is not supported"}.to_json
      end

      # Validate required parameters
      unless request_body["prompt"]
        status 400
        return {error: "The 'prompt' parameter is required."}.to_json
      end

      # Extract parameters with defaults
      prompt = request_body["prompt"]
      model = request_body["model"] || "flux"  # Default to flux model
      n = request_body["n"] || 1  # Number of images to generate
      size = request_body["size"] || "1024x1024"  # Image size

      # Validate n parameter
      unless n.is_a?(Integer) && n > 0 && n <= 10
        status 400
        return {error: "The 'n' parameter must be an integer between 1 and 10."}.to_json
      end

      # Parse size parameter
      width, height = parse_size_parameter(size)
      unless width && height
        status 400
        return {error: "Invalid 'size' parameter. Supported formats: '256x256', '512x512', '1024x1024'."}.to_json
      end

      # Map OpenAI model to our internal model
      internal_model = map_openai_model_to_internal(model)

      params = {
        width:, height:,
        model: internal_model,
        steps: (internal_model == "flux") ? 2 : 20,  # Default steps based on model
        seed: rand(1000000000)
      }

      generation_task = GenerationTask.create(
        user_id: "openai_api_user",  # Special user ID for API requests
        username: "OpenAI API User",
        status: "pending",
        prompt: prompt,
        parameters: params.to_json,
        workflow_type: internal_model,
        queued_at: Time.now
      )

      client = ImageGenerationClient.create

      params[:prompt] = prompt
      result = client.generate_and_wait(params) do |status, prompt_id, progress|
        if status == :running
          generation_task.mark_processing unless generation_task.started_at
        end
      end

      # Update task as completed
      generation_task.mark_completed(result[:filename], result[:prompt_id])

      # Save the image file
      image_path = "#{generation_task.file_path}/#{generation_task.output_filename}"
      File.binwrite(image_path, result[:image_data])

      # Add EXIF data
      Kernel.system("exiftool -config exiftool_config -PNG:prompt=\"#{generation_task.prompt}\" -overwrite_original #{image_path} > /dev/null 2>&1")

      # Read EXIF data
      exif_data = {}
      exif_output = `exiftool -j "#{image_path}" 2>/dev/null`
      begin
        exif_json = JSON.parse(exif_output)
        if exif_json.is_a?(Array) && exif_json.first
          exif_data = exif_json.first
          %w[SourceFile ExifToolVersion FileName Directory FilePermissions FileModifyDate FileAccessDate FileInodeChangeDate].each do |k|
            exif_data.delete(k)
          end
        end
      rescue JSON::ParserError
        # Ignore EXIF parsing errors
      end

      generation_task.set_exif_data(exif_data)

      # Notify WebSocket clients about new photo
      photo_relative_path = image_path.gsub(/^db\/photos\//, "")
      if defined?(PhotoGalleryWebSocket)
        PhotoGalleryWebSocket.notify_new_photo(photo_relative_path, generation_task.to_h)
      end

      # Encode the image data as base64
      base64_image = Base64.strict_encode64(File.read(image_path, mode: "rb"))

      # Calculate token usage (approximate)
      prompt_tokens = (prompt.length / 4.0).ceil  # Rough estimate
      image_tokens = (width * height / 1000.0).ceil  # Rough estimate based on image size
      total_tokens = prompt_tokens + image_tokens

      # Return OpenAI-compatible response
      {
        created: Time.now.to_i,
        data: [
          {
            b64_json: base64_image
          }
        ],
        usage: {
          total_tokens: total_tokens,
          input_tokens: prompt_tokens,
          output_tokens: image_tokens,
          input_tokens_details: {
            text_tokens: prompt_tokens,
            image_tokens: 0
          }
        }
      }.to_json
    rescue JSON::ParserError
      status 400
      {error: "Invalid JSON in request body"}.to_json
    rescue => e
      # Log the error for debugging
      puts "Error in /image/generations: #{e.class.name}: #{e.message}"
      puts e.backtrace.join("\n")

      status 500
      {error: "Internal server error: #{e.class.name}: #{e.message}"}.to_json
    end
  end

  private

  # Helper method to parse size parameter
  def parse_size_parameter(size)
    return nil unless size.is_a?(String)

    match = size.match(/^(\d+)x(\d+)$/)
    return nil unless match

    width = match[1].to_i
    height = match[2].to_i

    # Validate size is within reasonable bounds
    return nil if width < 256 || width > 2048 || height < 256 || height > 2048

    [width, height]
  end

  # Helper method to map OpenAI model names to internal model names
  def map_openai_model_to_internal(openai_model)
    case openai_model.downcase
    when "gpt-image-1", "dall-e-2", "dall-e-3"
      "flux"  # Default to flux for OpenAI model names
    when "flux", "qwen"
      openai_model.downcase  # Use as-is if it's already one of our models
    else
      "flux"  # Default to flux for unknown models
    end
  end
end
