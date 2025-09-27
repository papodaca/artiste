require "open-uri"
require "base64"
require "httparty"
require "tempfile"
require "mini_magick"

class EditCommand < BaseCommand
  def self.parse(prompt)
    # Parse the prompt using PromptParameterParser
    parser = PromptParameterParser.new
    result = parser.parse(prompt, "qwen-image-edit")

    if result.is_a?(Hash) && result[:error]
      return {error: result[:error]}
    end

    result
  end

  def execute
    debug_log("Handling edit command")

    if parsed_result[:error]
      server.respond(message, "❌ #{parsed_result[:error]}")
      return
    end

    # Check if we have any image source (attached images, image parameter, or task_id)
    has_attached_images = message["attached_files"]&.any?
    has_image_param = parsed_result[:image].present?
    has_task_id = parsed_result[:task_id].present?

    unless has_attached_images || has_image_param || has_task_id
      server.respond(message, "❌ Please provide either an image URL using --image <url>, a filename using --image <filename>, a task ID using --task <id> parameter, or attach an image to your message for editing.")
      return
    end

    # Validate that we don't have both image and task_id parameters (attached images can be combined with either)
    if has_image_param && has_task_id
      server.respond(message, "❌ Please provide either an image (URL or filename) or a task ID, but not both. Attached images can be used with either option.")
      return
    end

    image_params = Array(parsed_result[:image])
    task_id = parsed_result[:task_id]
    prompt = parsed_result[:prompt]

    if prompt.nil? || prompt.strip.empty?
      server.respond(message, "❌ Please provide a prompt for the edit command.")
      return
    end

    image_sources = []
    image_sources << "attached images" if message["attached_files"]&.any?
    image_sources << image_params.join(", ") if image_params.any?
    image_sources << "from task " + task_id.to_s if task_id

    debug_log("Editing #{image_sources.join(" and ")} with prompt: #{prompt}")

    begin
      # Create generation task at the beginning
      generation_task = create_generation_task

      # Send initial response
      total_images = (message["attached_files"]&.size || 0) + (image_params&.size || 0) + (task_id ? 1 : 0)
      initial_response = "🖼️ Editing your image#{"s" if total_images > 1}..."
      reply = server.respond(message, initial_response)

      # Get image data either from URLs, filenames, attached images, or from task record
      base64_images = []

      # Process attached images first (from message attachments)
      if message["attached_files"]&.any?
        message["attached_files"].each do |attached_file|
          if attached_file.start_with?("http://", "https://")
            # It's a URL (Discord attachments)
            image_data = download_image(attached_file)
          elsif attached_file.start_with?("file://")
            # It's a local file path (Mattermost attachments)
            file_path = attached_file.sub("file://", "")
            image_data = File.binread(file_path)
            image_data = validate_and_convert_image(image_data, "attached file")
          end
          base64_images << Base64.strict_encode64(image_data)
        end
      end

      # Process explicitly provided image parameters
      if image_params.any?
        image_params.each do |image_param|
          if image_param.start_with?("http://", "https://")
            # It's a URL
            image_data = download_image(image_param)
          else
            # It's a filename, look up the task and load the image
            task = find_task_by_filename(image_param)
            image_data = load_image_from_task(task.id)
          end
          base64_images << Base64.strict_encode64(image_data)
        end
      elsif task_id
        image_data = load_image_from_task(task_id)
        base64_images << Base64.strict_encode64(image_data)
      end

      # Generate the edited image
      client = ImageGenerationClient.create
      params = parsed_result.merge(image_b64s: base64_images)

      result = client.generate(params) do |status, prompt_id, error|
        case status
        when :started
          # Update task with started_at timestamp
          update_generation_task_started(generation_task)
          server.update(message, reply, "🖼️ Editing your image... (processing)")
        when :completed
          # Update task with completed_at timestamp and processing time
          update_generation_task_completed(generation_task, prompt_id)
          server.update(message, reply, "✅ Image edit completed! Downloading result...")
        end
      end

      server.update(message, reply, "✅ Image edit completed successfully!")

      file_data = result[:image_data]
      image_path = "#{generation_task.file_path}/#{generation_task.output_filename}"
      File.binwrite(image_path, file_data)

      server.update(message, reply, "", Kernel.open(image_path, "rb"), generation_task.output_filename)

      photo_relative_path = image_path.gsub(/^db\/photos\//, "")

      # Notify WebSocket clients about new photo
      if defined?(PhotoGalleryWebSocket)
        task_data = {
          output_filename: generation_task.output_filename,
          username: generation_task.username,
          workflow_type: generation_task.workflow_type,
          completed_at: generation_task.completed_at&.strftime("%Y-%m-%d %H:%M:%S"),
          prompt: generation_task.prompt
        }
        PhotoGalleryWebSocket.notify_new_photo(photo_relative_path, task_data)
      end

      Kernel.system("exiftool -config exiftool_config -PNG:prompt=\"#{generation_task.prompt}\" -overwrite_original #{image_path} > /dev/null 2>&1")

      exif_data = {}
      debug_log("Reading EXIF data from image file: #{image_path}")
      exif_output = `exiftool -j "#{image_path}" 2>/dev/null`
      begin
        exif_json = JSON.parse(exif_output)
        if exif_json.is_a?(Array) && exif_json.first
          exif_data = exif_json.first
          %w[SourceFile ExifToolVersion FileName Directory FilePermissions FileModifyDate FileAccessDate FileInodeChangeDate].each do |k|
            exif_data.delete(k)
          end
          debug_log("Successfully read EXIF data from image")
        end
      rescue JSON::ParserError => e
        debug_log("Failed to parse EXIF JSON: #{e.message}")
      end

      generation_task.set_exif_data(exif_data)
    rescue => e
      debug_log("Error editing image: #{e.message}\n#{e.backtrace.join("\n")}")
      # Mark task as failed if it exists
      if defined?(generation_task) && generation_task
        mark_generation_task_failed(generation_task, e.message)
      end
      server.respond(message, "❌ Error editing image: #{e.message}")
    end
  end

  private

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

  def create_generation_task
    debug_log("Creating generation task")

    # Create a generation task record
    task = GenerationTask.create(
      user_id: user_settings.user_id,
      username: user_settings.username,
      status: "pending",
      prompt: parsed_result[:prompt],
      parameters: parsed_result.except(:prompt, :image, :image_b64, :task_id).to_json,
      workflow_type: "qwen-image-edit",
      queued_at: Time.now
    )

    debug_log("Created generation task #{task.id}")
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

    task.mark_completed("chutes_#{Time.now.to_i}.png", prompt_id)
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
end
