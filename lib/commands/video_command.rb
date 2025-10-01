class VideoCommand < BaseCommand
  # Resolution options
  SIXTEEN_NINE = "1280*720"
  NINE_SIXTEEN = "720*1280"
  WIDESCREEN = "832*480"
  PORTRAIT = "480*832"
  SQUARE = "1024*1024"

  # Aspect ratio constants
  ASPECT_RATIO_16_9 = 16.0 / 9.0
  ASPECT_RATIO_9_16 = 9.0 / 16.0
  ASPECT_RATIO_SQUARE = 1.0

  def self.select_resolution_by_aspect_ratio(aspect_ratio)
    # Define tolerance for aspect ratio comparison
    tolerance = 0.1

    # Compare with supported aspect ratios and return appropriate resolution
    if (aspect_ratio - ASPECT_RATIO_16_9).abs <= tolerance
      SIXTEEN_NINE
    elsif (aspect_ratio - ASPECT_RATIO_9_16).abs <= tolerance
      NINE_SIXTEEN
    elsif (aspect_ratio - ASPECT_RATIO_SQUARE).abs <= tolerance
      SQUARE
    elsif aspect_ratio > ASPECT_RATIO_16_9
      # Wider than 16:9, use widescreen
      WIDESCREEN
    else
      # Taller than 9:16, use portrait
      PORTRAIT
    end
  end

  def self.parse_aspect_ratio(aspect_ratio)
    parts = aspect_ratio.split(":")
    return 1.0 if parts.size != 2
    parts.first.to_f / parts.last.to_f
  end

  def self.parse(prompt)
    result = PromptParameterParser.parse(prompt, "wan2.2")
    prompt = result[:prompt]
    resolution = select_resolution_by_aspect_ratio(parse_aspect_ratio(result[:aspect_ratio] || "1:1"))

    # Parse frames
    frames = if (match = prompt.match(/--frames\s+(\d+)/))
      match[1].to_i
    elsif (match = prompt.match(/-f\s+(\d+)/))
      match[1].to_i
    end

    # Parse guidance scale
    guidance = if (match = prompt.match(/--guidance\s+(\d+\.?\d*)/))
      match[1].to_f
    elsif (match = prompt.match(/-g\s+(\d+\.?\d*)/))
      match[1].to_f
    end

    prompt = prompt
      .gsub(/--frames\s+\d+/, "")
      .gsub(/--guidance\s+\d+\.?\d*/, "")
      .gsub(/-f\s+\d+/, "")
      .gsub(/-g\s+\d+\.?\d*/, "")
      .strip

    result.merge(resolution:, frames:, guidance:, prompt:)
  end

  def execute
    debug_log("Handling video command")
    prompt = parsed_result[:prompt]
    resolution = parsed_result[:resolution]
    seed = parsed_result[:seed]
    steps = parsed_result[:steps] || 25
    shift = parsed_result[:shift]
    frames = parsed_result[:frames] || 81
    guidance_scale = parsed_result[:guidance_scale] || 5.0
    negative_prompt = parsed_result[:negative_prompt]

    # Check if we have an image source (attached images, image parameter, or task_id)
    attached_images_count = message["attached_files"]&.size || 0
    image_params_count = if parsed_result[:image].is_a?(Array)
      parsed_result[:image].size
    else
      (parsed_result[:image].present? ? 1 : 0)
    end
    task_id_count = parsed_result[:task_id].present? ? 1 : 0

    total_images = attached_images_count + image_params_count + task_id_count
    has_image = total_images > 0

    # Validate that we don't have multiple images
    if has_image && total_images > 1
      server.respond(message, "❌ Video generation from image only supports one image at a time. You provided #{total_images} images.")
      return
    end

    if prompt.nil? || prompt.strip.empty?
      debug_log("No prompt provided for video command")
      server.respond(message, "❌ Please provide a prompt for the video command.")
      return
    end

    debug_log("Generating video for prompt: #{prompt}#{" with image" if has_image}")

    begin
      # Create generation task at the beginning
      generation_task = create_generation_task
      generation_task.private = parsed_result.has_key?(:private)
      generation_task.save

      # Send initial response
      initial_response = has_image ? "🎬 Generating video from image..." : "🎬 Generating video..."
      reply = server.respond(message, initial_response)

      # Then generate the video and update the message
      if has_image
        generate_image2video(prompt, reply, resolution, seed, steps, shift, frames, guidance_scale, negative_prompt, generation_task)
      else
        generate_video(prompt, reply, resolution, seed, steps, shift, frames, guidance_scale, negative_prompt, generation_task)
      end
    rescue => e
      debug_log("Error generating video: #{e.message}")
      # Mark task as failed if it exists
      if defined?(generation_task) && generation_task
        mark_generation_task_failed(generation_task, e.message)
      end
      server.respond(message, "❌ Sorry, I encountered an error while generating the video: #{e.message}")
    end
  end

  private

  def generate_video(prompt, reply, resolution, seed, steps, shift, frames, guidance_scale, negative_prompt, generation_task)
    # Get API token from environment variables
    api_token = ENV["CHUTES_API_TOKEN"]

    # Validate API token
    if api_token.nil? || api_token.strip.empty?
      raise "Chutes API token is not configured. Please set the CHUTES_API_TOKEN environment variable."
    end

    # Update task as started
    update_generation_task_started(generation_task)
    server.update(message, reply, "🎬 Generating video... (processing)")

    # Create Chutes HTTP client
    http_client = ChutesHttpClient.new(nil, api_token)

    # Prepare the payload
    payload = {
      resolution: resolution,
      seed: seed,
      steps: steps,
      frames: frames,
      prompt: prompt,
      sample_shift: shift,
      single_frame: false,
      guidance_scale: guidance_scale,
      negative_prompt: negative_prompt
    }

    # Generate the video
    result = http_client.generate_video(payload)

    # Update task as completed
    update_generation_task_completed(generation_task, result[:prompt_id])
    server.update(message, reply, "✅ Video generated! Uploading...")

    # Create the final output path
    video_path = "#{generation_task.file_path}/#{generation_task.output_filename}"
    FileUtils.mkdir_p(File.dirname(video_path))
    File.write(video_path, result[:video_data])

    server.update(
      message,
      reply,
      debug_log_enabled ? parsed_result.to_json : "",
      File.open(video_path, "rb"),
      generation_task.output_filename
    )

    if defined?(PhotoGalleryWebSocket)
      PhotoGalleryWebSocket.notify_new_photo(video_path, generation_task.to_h)
    end
  rescue => e
    debug_log("Error generating video: #{e.message}")
    server.update(message, reply, "❌ Sorry, I encountered an error while generating the video: #{e.message}")
  end

  def generate_image2video(prompt, reply, resolution, seed, steps, shift, frames, guidance_scale, negative_prompt, generation_task)
    require "base64"
    require "httparty"
    require "tempfile"
    require "mini_magick"

    # Get API token from environment variables
    api_token = ENV["CHUTES_API_TOKEN"]

    # Validate API token
    if api_token.nil? || api_token.strip.empty?
      raise "Chutes API token is not configured. Please set the CHUTES_API_TOKEN environment variable."
    end

    # Update task as started
    update_generation_task_started(generation_task)
    server.update(message, reply, "🎬 Generating video from image... (processing)")

    # Get image data either from URLs, filenames, attached images, or from task record
    base64_image = nil
    image_param = parsed_result[:image]
    task_id = parsed_result[:task_id]

    # Process attached images first (from message attachments)
    if message["attached_files"]&.any?
      attached_file = message["attached_files"].first
      if attached_file.start_with?("http://", "https://")
        # It's a URL (Discord attachments)
        image_data = download_image(attached_file)
      elsif attached_file.start_with?("file://")
        # It's a local file path (Mattermost attachments)
        file_path = attached_file.sub("file://", "")
        image_data = File.binread(file_path)
        image_data = validate_and_convert_image(image_data, "attached file")
      end
      base64_image = Base64.strict_encode64(image_data)
    elsif image_param
      if image_param.start_with?("http://", "https://")
        # It's a URL
        image_data = download_image(image_param)
      else
        # It's a filename, look up the task and load the image
        task = find_task_by_filename(image_param)
        image_data = load_image_from_task(task.id)
      end
      base64_image = Base64.strict_encode64(image_data)
    elsif task_id
      image_data = load_image_from_task(task_id)
      base64_image = Base64.strict_encode64(image_data)
    end

    # Create Chutes HTTP client
    http_client = ChutesHttpClient.new(nil, api_token)

    # Prepare the payload for image2video
    payload = {
      prompt: prompt,
      image_b64: base64_image,
      guidance_scale: guidance_scale || 5.0,
      resolution: resolution,
      sample_shift: shift,
      seed: seed,
      steps: steps,
      frames: frames,
      fps: 16,
      single_frame: false,
      negative_prompt: negative_prompt
    }

    # Generate the video from image
    result = http_client.generate_image2video(payload)

    # Update task as completed
    update_generation_task_completed(generation_task, result[:prompt_id])
    server.update(message, reply, "✅ Video generated! Uploading...")

    # Create the final output path
    video_path = "#{generation_task.file_path}/#{generation_task.output_filename}"
    FileUtils.mkdir_p(File.dirname(video_path))
    File.write(video_path, result[:video_data])

    server.update(
      message,
      reply,
      debug_log_enabled ? parsed_result.to_json : "",
      File.open(video_path, "rb"),
      generation_task.output_filename
    )

    if defined?(PhotoGalleryWebSocket)
      PhotoGalleryWebSocket.notify_new_photo(video_path, generation_task.to_h)
    end
  rescue => e
    debug_log("Error generating video from image: #{e.message}")
    server.update(message, reply, "❌ Sorry, I encountered an error while generating the video from image: #{e.message}")
  end

  def create_generation_task
    debug_log("Creating generation task")

    # Handle case where user_settings is nil (e.g., in tests)
    user_id = user_settings ? user_settings.user_id : "test_user"
    username = user_settings ? user_settings.username : "test_user"

    # Determine workflow type based on whether we have an image
    attached_images_count = message["attached_files"]&.size || 0
    image_params_count = if parsed_result[:image].is_a?(Array)
      parsed_result[:image].size
    else
      (parsed_result[:image].present? ? 1 : 0)
    end
    task_id_count = parsed_result[:task_id].present? ? 1 : 0

    total_images = attached_images_count + image_params_count + task_id_count
    has_image = total_images > 0
    workflow_type = has_image ? "image2video" : "video-generation"

    # Create a generation task record
    task = GenerationTask.create(
      user_id: user_id,
      username: username,
      status: "pending",
      prompt: parsed_result[:prompt],
      parameters: parsed_result.except(:prompt).to_json,
      workflow_type: workflow_type,
      queued_at: Time.now
    )

    debug_log("Created generation task #{task.id} with workflow type: #{workflow_type}")
    task
  rescue => e
    debug_log("Error creating generation task: #{e.message}")
    raise "Failed to create generation task: #{e.message}"
  end

  def update_generation_task_started(task)
    debug_log("Updating generation task #{task.id} as started")

    task.mark_processing
    debug_log("Updated generation task #{task.id} as started")
  rescue => e
    debug_log("Error updating generation task as started: #{e.message}")
  end

  def update_generation_task_completed(task, prompt_id)
    debug_log("Updating generation task #{task.id} as completed")

    task.mark_completed("chutes_#{Time.now.to_i}.mp4", prompt_id)
    debug_log("Updated generation task #{task.id} as completed with processing time: #{task.processing_time_seconds}s")
  rescue => e
    debug_log("Error updating generation task as completed: #{e.message}")
  end

  def mark_generation_task_failed(task, error_message)
    debug_log("Marking generation task #{task.id} as failed")

    task.mark_failed(error_message)
    debug_log("Marked generation task #{task.id} as failed")
  rescue => e
    debug_log("Error marking generation task as failed: #{e.message}")
  end

  def validate_and_convert_image(image_data, source_description = "image")
    # Validate it's actually an image using MiniMagick
    begin
      # Create a temporary file to validate the image
      temp_image = Tempfile.new(["image_validation", ".bin"])
      temp_image.binmode
      temp_image.write(image_data)
      temp_image.close

      # Use MiniMagick to validate the image
      image = MiniMagick::Image.open(temp_image.path)
      image.validate! # This will raise an error if the file is not a valid image
    rescue MiniMagick::Error, MiniMagick::Invalid => e
      raise "#{source_description} doesn't appear to be a valid image: #{e.message}"
    ensure
      # Clean up the temporary file
      temp_image&.unlink
    end

    # Convert to PNG if it's not already in PNG format
    unless image_data[0..10].include?("PNG")
      debug_log("Converting #{source_description} to PNG format")

      # Create a temporary file for the original image
      temp_input = Tempfile.new(["original_image", ".bin"])
      temp_input.binmode
      temp_input.write(image_data)
      temp_input.close

      # Create a temporary file for the PNG output
      temp_output = Tempfile.new(["converted_image", ".png"])
      temp_output.close

      begin
        # Use ImageMagick to convert to PNG
        convert_result = system("magick convert \"#{temp_input.path}\" \"#{temp_output.path}\"")
        unless convert_result
          raise "Failed to convert #{source_description} to PNG using ImageMagick"
        end

        # Read the converted PNG data
        image_data = File.binread(temp_output.path)
        debug_log("Successfully converted #{source_description} to PNG")
      ensure
        # Clean up temporary files
        temp_input.unlink
        temp_output.unlink
      end
    end

    image_data
  end

  def download_image(url)
    debug_log("Downloading image from: #{url}")

    # Validate URL
    unless url&.match?(URI::DEFAULT_PARSER.make_regexp)
      raise "Invalid image URL: #{url}"
    end

    # Download the image
    response = HTTParty.get(url)

    # Check if the request was successful
    unless response.success?
      raise "Failed to download image: HTTP error #{response.code} - #{response.message}"
    end

    image_data = response.body

    # Validate and convert the image
    validate_and_convert_image(image_data, "downloaded file")
  rescue SocketError, Timeout::Error => e
    raise "Failed to download image: Network error #{e.message}"
  rescue HTTParty::Error, HTTParty::ResponseError => e
    raise "Failed to download image: HTTParty error #{e.message}"
  rescue => e
    raise "Failed to download image: #{e.message}"
  end

  def find_task_by_filename(filename)
    debug_log("Looking up task by filename: #{filename}")

    # Validate filename format
    unless /^[a-zA-Z0-9_-]+\.(png|jpg|jpeg|gif|webp)$/i.match?(filename)
      raise "Invalid filename format: #{filename}. Expected format: filename.extension"
    end

    # Find the task record by output_filename
    task = GenerationTask.where(output_filename: filename).first
    unless task
      raise "No task found with filename: #{filename}"
    end

    # Check if task has required fields
    unless task.output_filename
      raise "Task #{task.id} does not have an associated output filename"
    end

    unless task.completed_at
      raise "Task #{task.id} is not completed"
    end

    debug_log("Found task #{task.id} for filename: #{filename}")
    task
  end

  def load_image_from_task(task_id)
    debug_log("Loading image from task ID: #{task_id}")

    # Find the task record
    task = GenerationTask[task_id]
    unless task
      raise "Task with ID #{task_id} not found"
    end

    # Check if task has an output filename
    unless task.output_filename
      raise "Task #{task_id} does not have an associated image file"
    end

    # Construct the full path to the image file
    image_path = File.join(task.file_path, task.output_filename)

    # Check if the file exists
    unless File.exist?(image_path)
      raise "Image file not found at: #{image_path}"
    end

    # Read the image data
    image_data = File.binread(image_path)

    # Validate and convert the image
    image_data = validate_and_convert_image(image_data, "file")

    debug_log("Successfully loaded image from task #{task_id}: #{image_path}")
    image_data
  rescue => e
    debug_log("Error loading image from task #{task_id}: #{e.message}")
    raise "Failed to load image from task #{task_id}: #{e.message}"
  end
end
