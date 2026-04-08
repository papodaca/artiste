# frozen_string_literal: true

class TranscribeCommand < BaseCommand
  def self.parse(prompt)
    text = prompt.to_s.sub(%r{^/transcribe\s*}, "")

    audio = if (match = text.match(%r{(?:--audio(?:=|\s+)|-a\s+)((?:https?://[^\s]+)|(?:[^\s]+\.(?:wav|mp3|ogg|flac|m4a|aac)))}i))
      match[1]
    end

    language = if (match = text.match(/(?:--language(?:=|\s+)|-l\s+)([a-z]{2,3})/i))
      match[1]
    end

    {audio: audio, language: language}.compact
  end

  def execute
    debug("Handling transcribe command")

    audio_param = parsed_result[:audio]
    language = parsed_result[:language]
    has_attached = message["attached_files"]&.any? { |f| audio_file?(f) }

    unless audio_param || has_attached
      server.respond(message, "❌ Please attach an audio file or provide `--audio <url>`.")
      return
    end

    reply = server.respond(message, "🎙️ Transcribing...")

    begin
      audio_b64 = if has_attached
        attached_file = message["attached_files"].find { |f| audio_file?(f) }
        process_audio_file(attached_file)
      else
        process_audio_file(audio_param)
      end

      client = ChutesHttpClient.new(nil, ENV["CHUTES_TOKEN"])
      result = client.transcribe_audio({audio_b64: audio_b64, language: language}.compact)

      debug("Transcription complete: #{result[:text]&.length} chars")
      server.update(message, reply, result[:text])
    rescue => e
      debug("Transcribe error: #{e.message}\n#{e.backtrace&.join("\n")}")
      server.update(message, reply, "❌ Transcription failed: #{e.message}")
    end
  end

  private

  def audio_file?(filename)
    return false unless filename

    filename.downcase.match?(/\.(wav|mp3|ogg|flac|m4a|aac)$/) ||
      (filename.include?("://") && !filename.match?(/\.(png|jpg|jpeg|tiff|bmp|webp|gif)$/i))
  end

  def process_audio_file(file_path_or_url)
    if file_path_or_url.start_with?("http://", "https://")
      audio_data = HTTParty.get(file_path_or_url).body
    elsif file_path_or_url.start_with?("file://")
      audio_data = File.binread(file_path_or_url.sub("file://", ""))
    else
      raise "Unknown audio source: #{file_path_or_url}"
    end

    Base64.strict_encode64(convert_to_wav_if_needed(audio_data))
  end

  def convert_to_wav_if_needed(audio_data)
    temp_input = Tempfile.new(["audio_input", ".bin"])
    temp_input.binmode
    temp_input.write(audio_data)
    temp_input.close

    format = `ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "#{temp_input.path}" 2>/dev/null`.strip
    is_wav = %w[pcm_s16le pcm_s24le pcm_s32le].include?(format.downcase)

    result = if is_wav
      audio_data
    else
      debug("Converting audio to WAV format (detected: #{format})")
      temp_output = Tempfile.new(["audio_output", ".wav"])
      temp_output.close
      system("ffmpeg -y -i \"#{temp_input.path}\" -c:a pcm_s16le -ar 44100 \"#{temp_output.path}\" > /dev/null 2>&1")
      data = File.binread(temp_output.path)
      temp_output.unlink
      data
    end

    temp_input.unlink

    max_size = 5 * 1024 * 1024
    if result.bytesize > max_size
      raise "Audio file is too large (#{(result.bytesize.to_f / 1024 / 1024).round(2)} MB). Maximum allowed size is 5 MB."
    end

    result
  end
end
