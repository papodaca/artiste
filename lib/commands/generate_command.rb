class GenerateCommand < BaseCommand
  def self.parse(prompt)
    # Parse the prompt using PromptParameterParser
    parser = PromptParameterParser.new
    result = parser.parse(prompt, "flux")

    return {error: result[:error]} if result.is_a?(Hash) && result[:error]

    result
  end

  def execute
    debug("Handling generate command")

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

    debug("Processing generate command for user_id: #{user_id}, username: #{username}")

    # Get the full prompt
    full_prompt = message["message"].gsub(/<?@\w+>?\s*/, "").strip
    debug("Extracted prompt: '#{full_prompt}'")

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
    debug("Created generation task ##{generation_task.id}")

    # Send initial response
    reply = server.respond(message, "🎨 Image generation queued...")

    debug("Queued image generation process for task ##{generation_task.id}")

    debug("User settings: #{user_params.inspect}")
    debug("Final parameters for generation: #{final_params.inspect}")

    # Get the image generation client
    image_generation_client = ImageGenerationClient.create

    # Generate image using the appropriate client
    if image_generation_client.is_a?(ComfyuiClient)
      result = image_generation_client.generate_and_wait(final_params,
        1.hour.seconds.to_i) do |kind, prompt_id, progress|
        if prompt_id.present? && prompt_id != generation_task.prompt_id
          debug("Setting the generation task's prompt_id to #{prompt_id}")
          generation_task.prompt_id = prompt_id
          generation_task.save
        end
        if kind == :running
          debug("Starting image generation process for task ##{generation_task.id}")
          generation_task.mark_processing
          server.update(message, reply,
            "🎨 Generating image... This may take a few minutes.#{final_params.to_json if debug?}")
        end
        if kind == :progress
          debug("Generation progress for task ##{generation_task.id}, #{progress.join(", ")}")
          server.update(message, reply, "🎨 Generating image... This may take a few minutes. progressing: #{progress.map do |p|
            p.to_s + "%"
          end.join(", ")}.#{final_params.to_json if debug?}")
        end
      end
    else # Chutes or other clients
      # For Chutes, we'll simulate the progress callbacks since it doesn't have the same progress tracking
      server.update(message, reply,
        "🎨 Generating image... This may take a few minutes.#{final_params.to_json if debug?}")
      generation_task.mark_processing

      result = image_generation_client.generate(final_params)

      # Simulate completion callback
      debug("Image generation completed successfully for task ##{generation_task.id}")
      server.update(message, reply, "🎨 Image generation completed!#{final_params.to_json if debug?}")
    end
    debug("Image generation completed successfully for task ##{generation_task.id}")

    filename = result[:filename]
    generation_task.mark_completed(filename)
    target_dir = generation_task.file_path
    filepath = File.join(target_dir, filename)
    File.write(filepath, result[:image_data])

    # Notify WebSocket clients about new photo
    PhotoGalleryWebSocket.notify_new_photo(filepath, generation_task.to_h) if defined?(PhotoGalleryWebSocket)

    if generation_task.prompt_id.nil? && result.has_key?(:prompt_id)
      generation_task.prompt_id = result[:prompt_id]
      generation_task.save
    end

    Kernel.system("exiftool -config exiftool_config -PNG:prompt=\"#{generation_task.prompt}\" -overwrite_original #{filepath} > /dev/null 2>&1")

    exif_data = {}
    debug("Reading EXIF data from image file: #{filepath}")
    exif_output = `exiftool -j "#{filepath}" 2>/dev/null`
    begin
      exif_json = JSON.parse(exif_output)
      if exif_json.is_a?(Array) && exif_json.first
        exif_data = exif_json.first
        %w[SourceFile ExifToolVersion FileName Directory FilePermissions FileModifyDate FileAccessDate
          FileInodeChangeDate].each do |k|
          exif_data.delete(k)
        end
        debug("Successfully read EXIF data from image")
      end
    rescue JSON::ParserError => e
      debug("Failed to parse EXIF JSON: #{e.message}")
    end

    generation_task.set_exif_data(exif_data) unless exif_data.empty?

    server.update(
      message,
      reply,
      debug? ? final_params.to_json : "",
      File.open(filepath, "rb"),
      filepath
    )
  rescue => e
    error_msg = "❌ Image generation failed: #{e.message}"
    debug("Error generating image: #{e.message}")
    debug(e.backtrace)
    debug("Image generation error: #{e.message}")
    debug("Error backtrace: #{e.backtrace.join("\n")}")

    # Mark task as failed
    generation_task.mark_failed(e.message)

    server.update(message, reply, error_msg)
    server.respond(message, "```#{error_msg}\n#{e.backtrace.join("\n")}```")
  end
end
