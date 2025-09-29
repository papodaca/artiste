class GenerateCommand < BaseCommand
  def self.parse(prompt)
    # Parse the prompt using PromptParameterParser
    parser = PromptParameterParser.new
    result = parser.parse(prompt, "flux")

    if result.is_a?(Hash) && result[:error]
      return {error: result[:error]}
    end

    result
  end

  def execute
    debug_log("Handling generate command")

    if parsed_result[:error]
      server.respond(message, "❌ #{parsed_result[:error]}")
      return
    end

    # Get user information
    user_id = nil
    username = "unknown"
    if server.is_a?(MattermostServerStrategy)
      user_id = message.dig("data", "post", "user_id")
      username = message.dig("data", "channel_display_name")&.gsub(/@/, "") || message.dig("user", "username") || "unknown"
    elsif server.is_a?(DiscordServerStrategy)
      user_id = message["user"].id
      username = message["user"].username
    end

    debug_log("Processing generate command for user_id: #{user_id}, username: #{username}")

    # Get the full prompt
    full_prompt = message["message"].gsub(/<?@\w+>?\s*/, "").strip
    debug_log("Extracted prompt: '#{full_prompt}'")

    if full_prompt.empty?
      server.respond(message, "Please provide a prompt for image generation!")
      return
    end

    # Create generation task record
    user_params = user_settings.parsed_prompt_params
    final_params = PromptParameterParser.resolve_params(parsed_result.merge(user_params))

    generation_task = GenerationTask.create(
      user_id: user_id,
      username: username,
      prompt: full_prompt,
      parameters: final_params.to_json,
      workflow_type: final_params[:model] || "flux",
      status: "pending",
      private: final_params.has_key?(:private)
    )
    debug_log("Created generation task ##{generation_task.id}")

    # Send initial response
    reply = server.respond(message, "🎨 Image generation queued...")

    debug_log("Queued image generation process for task ##{generation_task.id}")

    debug_log("User settings: #{user_params.inspect}")
    debug_log("Final parameters for generation: #{final_params.inspect}")

    # Get the image generation client
    image_generation_client = ImageGenerationClient.create

    # Generate image using the appropriate client
    if image_generation_client.is_a?(ComfyuiClient)
      result = image_generation_client.generate_and_wait(final_params, 1.hour.seconds.to_i) do |kind, comfyui_prompt_id, progress|
        if comfyui_prompt_id.present? && comfyui_prompt_id != generation_task.comfyui_prompt_id
          debug_log("Setting the generation task's comfyui_prompt_id to #{comfyui_prompt_id}")
          generation_task.comfyui_prompt_id = comfyui_prompt_id
          generation_task.save
        end
        if kind == :running
          debug_log("Starting image generation process for task ##{generation_task.id}")
          generation_task.mark_processing
          server.update(message, reply, "🎨 Generating image... This may take a few minutes.#{final_params.to_json if debug_log_enabled}")
        end
        if kind == :progress
          debug_log("Generation progress for task ##{generation_task.id}, #{progress.join(", ")}")
          server.update(message, reply, "🎨 Generating image... This may take a few minutes. progressing: #{progress.map { |p| p.to_s + "%" }.join(", ")}.#{final_params.to_json if debug_log_enabled}")
        end
      end
    else # Chutes or other clients
      # For Chutes, we'll simulate the progress callbacks since it doesn't have the same progress tracking
      server.update(message, reply, "🎨 Generating image... This may take a few minutes.#{final_params.to_json if debug_log_enabled}")
      generation_task.mark_processing

      result = image_generation_client.generate(final_params)

      # Simulate completion callback
      debug_log("Image generation completed successfully for task ##{generation_task.id}")
      server.update(message, reply, "🎨 Image generation completed!#{final_params.to_json if debug_log_enabled}")
    end
    debug_log("Image generation completed successfully for task ##{generation_task.id}")

    filename = result[:filename]
    generation_task.mark_completed(filename)
    target_dir = generation_task.file_path
    filepath = File.join(target_dir, filename)
    File.write(filepath, result[:image_data])

    # Get photo path for WebSocket notification (relative path without db/photos prefix)
    photo_relative_path = target_dir.gsub(/^db\/photos\//, "")
    photo_relative_path = File.join(photo_relative_path, filename)

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

    if generation_task.comfyui_prompt_id.nil? && result.has_key?(:prompt_id)
      generation_task.comfyui_prompt_id = result[:prompt_id]
      generation_task.save
    end

    Kernel.system("exiftool -config exiftool_config -PNG:prompt=\"#{generation_task.prompt}\" -overwrite_original #{filepath} > /dev/null 2>&1")

    exif_data = {}
    debug_log("Reading EXIF data from image file: #{filepath}")
    exif_output = `exiftool -j "#{filepath}" 2>/dev/null`
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

    unless exif_data.empty?
      generation_task.set_exif_data(exif_data)
    end

    server.update(
      message,
      reply,
      debug_log_enabled ? final_params.to_json : "",
      File.open(filepath, "rb"),
      filepath
    )
  rescue => e
    error_msg = "❌ Image generation failed: #{e.message}"
    debug_log("Error generating image: #{e.message}")
    debug_log(e.backtrace)
    debug_log("Image generation error: #{e.message}")
    debug_log("Error backtrace: #{e.backtrace.join("\n")}")

    # Mark task as failed
    generation_task.mark_failed(e.message)

    server.update(message, reply, error_msg)
    server.respond(message, "```#{error_msg}\n#{e.backtrace.join("\n")}```")
  end
end
