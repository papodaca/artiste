require "open-uri"
require "base64"

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

    # Check if either image parameter or task_id parameter is provided
    unless parsed_result[:image] || parsed_result[:task_id]
      server.respond(message, "❌ Please provide either an image URL using --image <url>, a filename using --image <filename>, or a task ID using --task <id> parameter for editing.")
      return
    end

    # Validate that we don't have both image and task_id parameters
    if parsed_result[:image] && parsed_result[:task_id]
      server.respond(message, "❌ Please provide either an image (URL or filename) or a task ID, but not both.")
      return
    end

    image_param = parsed_result[:image]
    task_id = parsed_result[:task_id]
    prompt = parsed_result[:prompt]

    if prompt.nil? || prompt.strip.empty?
      server.respond(message, "❌ Please provide a prompt for the edit command.")
      return
    end

    debug_log("Editing image #{image_param || 'from task ' + task_id.to_s} with prompt: #{prompt}")

    begin
      # Create generation task at the beginning
      generation_task = create_generation_task
      
      # Send initial response
      initial_response = "🖼️ Editing your image..."
      reply = server.respond(message, initial_response)

      # Get image data either from URL, filename, or from task record
      if image_param
        if image_param.start_with?('http://') || image_param.start_with?('https://')
          # It's a URL
          image_data = download_image(image_param)
        else
          # It's a filename, look up the task and load the image
          task = find_task_by_filename(image_param)
          image_data = load_image_from_task(task.id)
        end
      elsif task_id
        image_data = load_image_from_task(task_id)
      end
      
      base64_image = Base64.strict_encode64(image_data)

      # Generate the edited image
      client = ImageGenerationClient.create
      params = parsed_result.merge(image_b64: base64_image)
      
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
      File.open(image_path, "wb") do |file|
        file.write(file_data)
      end

      server.update(message, reply, "", open(image_path, "rb"), generation_task.output_filename)

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

  def download_image(url)
    debug_log("Downloading image from: #{url}")
    
    # Validate URL
    unless url =~ URI::DEFAULT_PARSER.make_regexp
      raise "Invalid image URL: #{url}"
    end

    # Download the image
    URI.open(url) do |file|
      image_data = file.read
      
      # Validate it's actually an image
      unless image_data[0..10].include?("PNG") || image_data[0..10].include?("JFIF") || image_data[0..10].include?("Exif")
        raise "Downloaded file doesn't appear to be a valid image (PNG/JPEG)"
      end
      
      image_data
    end
  rescue OpenURI::HTTPError => e
    raise "Failed to download image: HTTP error #{e.message}"
  rescue SocketError, Timeout::Error => e
    raise "Failed to download image: Network error #{e.message}"
  rescue => e
    raise "Failed to download image: #{e.message}"
  end

  def find_task_by_filename(filename)
    debug_log("Looking up task by filename: #{filename}")
    
    # Validate filename format
    unless filename =~ /^[a-zA-Z0-9_-]+\.(png|jpg|jpeg|gif|webp)$/i
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
    
    # Validate it's actually an image
    unless image_data[0..10].include?("PNG") || image_data[0..10].include?("JFIF") || image_data[0..10].include?("Exif")
      raise "File doesn't appear to be a valid image (PNG/JPEG)"
    end
    
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
      status: 'pending',
      prompt: parsed_result[:prompt],
      parameters: parsed_result.except(:prompt, :image, :image_b64, :task_id).to_json,
      workflow_type: 'qwen-image-edit',
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