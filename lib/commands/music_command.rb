class MusicCommand < BaseCommand
  def self.parse(prompt)
    result = PromptParameterParser.new.parse(prompt, "diffrhythm")

    return {error: result[:error]} if result.is_a?(Hash) && result[:error]

    text = prompt.sub(%r{^/music\s+}, "")

    audio = if (match = text.match(%r{(?:--audio(?:=|\s+)|-a\s+)((?:https?://[^\s]+)|(?:[^\s]+\.(?:wav|mp3|ogg|flac|m4a|aac)))}))
      match[1]
    end

    lyrics = if (match = text.match(/(?:--lyrics(?:=|\s+)|-l\s+)([\s\S]+?)(?=\s*(?:--|\z))/))
      match[1].strip
    end

    duration = if (match = text.match(/(?:--duration(?:=|\s+)|-d\s+)(\d+)/))
      match[1].to_i
    end

    cfg = if (match = text.match(/--cfg(?:=|\s+)(\d+\.?\d*)/))
      match[1].to_f
    end

    scheduler = if (match = text.match(/--scheduler(?:=|\s+)(euler|midpoint|rk4)/))
      match[1]
    end

    batch = if (match = text.match(/(?:--batch(?:=|\s+)|-b\s+)(\d+)/))
      match[1].to_i
    end

    style_prompt = text
      .gsub(%r{(?:--audio(?:=|\s+)|-a\s+)(?:https?://[^\s]+|[^\s]+\.(?:wav|mp3|ogg|flac|m4a|aac))}, "")
      .gsub(/(?:--lyrics(?:=|\s+)|-l\s+)[\s\S]+?(?=\s*(?:--|\z))/, "")
      .gsub(/(?:--duration(?:=|\s+)|-d\s+)\d+/, "")
      .gsub(/--cfg(?:=|\s+)\d+\.?\d*/, "")
      .gsub(/--scheduler(?:=|\s+)(euler|midpoint|rk4)/, "")
      .gsub(/(?:--batch(?:=|\s+)|-b\s+)\d+/, "")
      .gsub(/--seed(?:=|\s+)\d+/, "")
      .gsub(/(?:--steps(?:=|\s+)|-s\s+)\d+/, "")
      .gsub(/\s+/, " ")
      .strip

    result.merge(
      style_prompt: style_prompt,
      audio: audio,
      lyrics: lyrics,
      duration: duration,
      cfg: cfg,
      scheduler: scheduler,
      batch: batch
    ).compact
  end

  def execute
    debug_log("Handling music command")

    if parsed_result[:error]
      server.respond(message, "❌ #{parsed_result[:error]}")
      return
    end

    style_prompt = parsed_result[:style_prompt]
    lyrics = parsed_result[:lyrics]
    audio_param = parsed_result[:audio]
    duration = parsed_result[:duration] || 285
    seed = parsed_result[:seed] || rand(1_000_000_000)
    cfg = parsed_result[:cfg] || 4.0
    steps = parsed_result[:steps] || 32
    scheduler = parsed_result[:scheduler] || "euler"
    batch_size = parsed_result[:batch] || 1

    has_audio_param = audio_param.present?
    has_attached_audio = message["attached_files"]&.any? { |f| audio_file?(f) }
    has_style_prompt = style_prompt.present? && !style_prompt.strip.empty?

    unless has_style_prompt || has_audio_param || has_attached_audio
      server.respond(message, "❌ Please provide either a style prompt or an audio file (via --audio or attachment).")
      return
    end

    unless (15..285).cover?(duration)
      server.respond(message, "❌ Duration must be between 15 and 285 seconds. Got: #{duration}")
      return
    end

    unless (1..4).cover?(batch_size)
      server.respond(message, "❌ Batch size must be between 1 and 4. Got: #{batch_size}")
      return
    end

    debug_log("Generating music - style: #{style_prompt}, lyrics: #{lyrics}, duration: #{duration}s")

    begin
      generation_task = create_generation_task

      initial_response = "🎵 Generating music..."
      reply = server.respond(message, initial_response)

      update_generation_task_started(generation_task)
      server.update(message, reply, "🎵 Generating music... (processing)")

      audio_b64 = nil
      if has_attached_audio
        attached_file = message["attached_files"].find { |f| audio_file?(f) }
        audio_b64 = process_audio_file(attached_file)
      elsif has_audio_param
        audio_b64 = process_audio_param(audio_param)
      end

      client = ChutesHttpClient.new(nil, ENV["CHUTES_TOKEN"])

      music_payload = {
        style_prompt: style_prompt,
        lyrics: lyrics,
        audio_b64: audio_b64,
        music_duration: duration,
        seed: seed,
        cfg_strength: cfg,
        steps: steps,
        scheduler: scheduler,
        chunked: false,
        batch_size: batch_size
      }.compact

      album_art_payload = {
        prompt: "flat abstract album cover for this style of music: #{style_prompt}",
        width: 1024,
        height: 1024,
        seed: seed,
        num_inference_steps: 20
      }

      music_result = nil
      album_art_result = nil
      album_art_error = nil

      music_thread = Thread.new do
        music_result = client.generate_music(music_payload)
      end

      album_art_thread = Thread.new do
        album_art_result = client.generate_image(album_art_payload, model: "z-image")
      rescue => e
        album_art_error = e
        debug_log("Album art generation failed: #{e.message}")
      end

      music_thread.join
      album_art_thread.join

      raise "Music generation failed" unless music_result

      update_generation_task_completed(generation_task, music_result[:prompt_id])
      server.update(message, reply, "✅ Music generated! Converting to M4A...")

      wav_data = music_result[:audio_data]
      output_path = music_file_path(generation_task)
      FileUtils.mkdir_p(output_path)

      temp_wav = Tempfile.new(["music", ".wav"])
      temp_wav.binmode
      temp_wav.write(wav_data)
      temp_wav.close

      base_filename = generation_task.output_filename.sub(/\.m4a$/, "")
      final_path = "#{output_path}/#{generation_task.output_filename}"

      if album_art_result && !album_art_error
        cover_path = "#{output_path}/cover_#{base_filename}.png"
        File.binwrite(cover_path, album_art_result[:image_data])
        debug_log("Saved album art to #{cover_path}")

        system("ffmpeg -y -i \"#{temp_wav.path}\" -i \"#{cover_path}\" -map 0 -map 1 -c:a aac -b:a 256k -c:v mjpeg -disposition:v:0 attached_pic \"#{final_path}\" > /dev/null 2>&1")
      else
        system("ffmpeg -y -i \"#{temp_wav.path}\" -c:a aac -b:a 256k \"#{final_path}\" > /dev/null 2>&1")
      end

      temp_wav.unlink

      server.update(message, reply, "", File.open(final_path, "rb"), generation_task.output_filename)

      PhotoGalleryWebSocket.notify_new_photo(final_path, generation_task.to_h) if defined?(PhotoGalleryWebSocket)
    rescue => e
      debug_log("Error generating music: #{e.message}\n#{e.backtrace.join("\n")}")
      if defined?(generation_task) && generation_task
        mark_generation_task_failed(generation_task, e.message)
      end
      server.respond(message, "❌ Error generating music: #{e.message}")
    end
  end

  private

  def audio_file?(filename)
    return false unless filename

    filename.downcase.match?(/\.(wav|mp3|ogg|flac|m4a|aac)$/) ||
      filename.include?("://") && !filename.match?(/\.(png|jpg|jpeg|tiff|bmp|webp|gif)$/i)
  end

  def process_audio_file(file_path_or_url)
    if file_path_or_url.start_with?("http://", "https://")
      audio_data = HTTParty.get(file_path_or_url).body
    elsif file_path_or_url.start_with?("file://")
      audio_data = File.binread(file_path_or_url.sub("file://", ""))
    else
      raise "Unknown audio source format: #{file_path_or_url}"
    end

    audio_data = convert_to_wav_if_needed(audio_data)
    Base64.strict_encode64(audio_data)
  end

  def process_audio_param(audio_param)
    if audio_param.start_with?("http://", "https://")
      audio_data = HTTParty.get(audio_param).body
    else
      task = find_task_by_filename(audio_param)
      audio_path = File.join(task.file_path, task.output_filename)
      raise "Audio file not found at: #{audio_path}" unless File.exist?(audio_path)

      audio_data = File.binread(audio_path)
    end

    audio_data = convert_to_wav_if_needed(audio_data)
    Base64.strict_encode64(audio_data)
  end

  def convert_to_wav_if_needed(audio_data)
    temp_input = Tempfile.new(["audio_input", ".bin"])
    temp_input.binmode
    temp_input.write(audio_data)
    temp_input.close

    format = `ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "#{temp_input.path}" 2>/dev/null`.strip
    is_wav = %w[pcm_s16le pcm_s24le pcm_s32le].include?(format.downcase)

    if is_wav
      result = audio_data
    else
      debug_log("Converting audio to WAV format (detected format: #{format})")
      temp_output = Tempfile.new(["audio_output", ".wav"])
      temp_output.close

      system("ffmpeg -y -i \"#{temp_input.path}\" -c:a pcm_s16le -ar 44100 \"#{temp_output.path}\" > /dev/null 2>&1")
      result = File.binread(temp_output.path)
      temp_output.unlink
    end

    temp_input.unlink

    max_size = 5 * 1024 * 1024
    if result.bytesize > max_size
      raise "Audio file is too large (#{(result.bytesize.to_f / 1024 / 1024).round(2)} MB). Maximum allowed size is 5 MB."
    end

    result
  end

  def find_task_by_filename(filename)
    debug_log("Looking up task by filename: #{filename}")
    task = GenerationTask.where(output_filename: filename).first
    raise "No task found with filename: #{filename}" unless task

    task
  end

  def music_file_path(task)
    time = task.completed_at || Time.now
    File.join(
      "db",
      "music",
      time.strftime("%Y"),
      time.strftime("%m"),
      time.strftime("%d")
    )
  end

  def create_generation_task
    debug_log("Creating generation task")

    user_id = user_settings ? user_settings.user_id : "test_user"
    username = user_settings ? user_settings.username : "test_user"

    task = GenerationTask.create(
      user_id: user_id,
      username: username,
      status: "pending",
      prompt: parsed_result[:style_prompt] || parsed_result[:lyrics] || "",
      parameters: parsed_result.except(:style_prompt, :prompt).to_json,
      workflow_type: "music",
      queued_at: Time.now
    )

    debug_log("Created generation task #{task.id}")
    task
  end

  def update_generation_task_started(task)
    debug_log("Updating generation task #{task.id} as started")
    task.mark_processing
  end

  def update_generation_task_completed(task, prompt_id)
    debug_log("Updating generation task #{task.id} as completed")
    task.mark_completed("chutes_#{Time.now.to_i}.m4a", prompt_id)
  end

  def mark_generation_task_failed(task, error_message)
    debug_log("Marking generation task #{task.id} as failed")
    task.mark_failed(error_message)
  end
end
