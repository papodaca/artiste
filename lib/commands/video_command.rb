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
    steps = parsed_result[:steps]
    frames = parsed_result[:frames] || 81
    guidance_scale = parsed_result[:guidance_scale] || 5.0
    negative_prompt = parsed_result[:negative_prompt]

    if prompt.nil? || prompt.strip.empty?
      debug_log("No prompt provided for video command")
      server.respond(message, "❌ Please provide a prompt for the video command.")
      return
    end

    debug_log("Generating video for prompt: #{prompt}")

    begin
      # Create generation task at the beginning
      generation_task = create_generation_task
      generation_task.private = parsed_result.has_key?(:private)
      generation_task.save

      # Send initial response
      initial_response = "🎬 Generating video..."
      reply = server.respond(message, initial_response)

      # Then generate the video and update the message
      generate_video(prompt, reply, resolution, seed, steps, frames, guidance_scale, negative_prompt, generation_task)
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

  def generate_video(prompt, reply, resolution, seed, steps, frames, guidance_scale, negative_prompt, generation_task)
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
      "resolution" => resolution,
      "seed" => seed,
      "steps" => steps,
      "frames" => frames,
      "prompt" => prompt,
      "sample_shift" => nil,
      "single_frame" => false,
      "guidance_scale" => guidance_scale,
      "negative_prompt" => negative_prompt
    }

    # Generate the video
    result = http_client.generate_video(payload)
    video_data = result[:video_data]
    prompt_id = result[:prompt_id]

    # Update task as completed
    update_generation_task_completed(generation_task, prompt_id)
    server.update(message, reply, "✅ Video generated! Uploading...")

    # Save the video to a temporary file
    temp_file = Tempfile.new(["video", ".mp4"])
    temp_file.binmode
    temp_file.write(video_data)
    temp_file.flush

    # Create the final output path
    video_path = "#{generation_task.file_path}/#{generation_task.output_filename}"
    FileUtils.mkdir_p(File.dirname(video_path))

    # Copy the video to the final location
    FileUtils.cp(temp_file.path, video_path)

    server.update(
      message,
      reply,
      debug_log_enabled ? parsed_result.to_json : "",
      File.open(video_path, "rb"),
      generation_task.output_filename
    )

    # Clean up the temporary file
    temp_file.close
    temp_file.unlink
  rescue => e
    debug_log("Error generating video: #{e.message}")
    server.update(message, reply, "❌ Sorry, I encountered an error while generating the video: #{e.message}")
  end

  def create_generation_task
    debug_log("Creating generation task")

    # Handle case where user_settings is nil (e.g., in tests)
    user_id = user_settings ? user_settings.user_id : "test_user"
    username = user_settings ? user_settings.username : "test_user"

    # Create a generation task record
    task = GenerationTask.create(
      user_id: user_id,
      username: username,
      status: "pending",
      prompt: parsed_result[:prompt],
      parameters: parsed_result.except(:prompt).to_json,
      workflow_type: "video-generation",
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
end
