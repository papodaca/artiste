---
title: "feat: Add Transcribe Command"
type: feat
status: active
date: 2026-03-24
---

# feat: Add Transcribe Command

Add a `/transcribe` slash command that accepts an attached audio file (or URL) and returns a text transcription using the Chutes Whisper Large v3 API at `https://chutes-whisper-large-v3.chutes.ai/transcribe`.

## Proposed Solution

Follow the established command pattern used by `MusicCommand`. The command will:

1. Accept an optional `--language` flag (e.g. `--language en`)
2. Accept audio via message attachment or `--audio <url>` parameter
3. Encode audio as base64 and POST JSON to the Chutes Whisper endpoint
4. Respond with the transcription text

## Technical Considerations

- **API payload**: Chutes Whisper v3 at `/transcribe` accepts JSON `{ audio_b64: "<base64>", language: "en" }` (language is optional)
- **Response**: Returns JSON with a `text` field containing the transcription
- **Auth**: Uses existing `CHUTES_TOKEN` env var (`ENV["CHUTES_TOKEN"]`)
- **Audio processing**: Reuse `process_audio_file` / `process_audio_param` patterns from `MusicCommand` — audio is downloaded, optionally converted to WAV via ffmpeg, and base64-encoded
- **File size limit**: Enforce existing 5 MB cap from `convert_to_wav_if_needed`
- **Supported formats**: WAV, MP3, OGG, FLAC, M4A, AAC (same as MusicCommand)
- **Discord**: `DiscordServerStrategy#download_attached_images` (`lib/discord_server_strategy.rb:114-133`) currently only handles images via `is_image_attachment?`. This will be extended to also download audio attachments (matching `audio/` content type) for parity with Mattermost's existing behaviour
- **No GenerationTask needed**: Transcription is text output only, no file stored; no DB record required

## System-Wide Impact

- **Interaction graph**: `/transcribe` → `CommandDispatcher.parse_command` → `TranscribeCommand.parse` → `TranscribeCommand#execute` → `ChutesHttpClient#transcribe_audio` → Chutes API → `server.respond`
- **Error propagation**: API failures raise and are rescued in `execute`, posting an error message via `server.respond`
- **State lifecycle risks**: Stateless — no DB writes, no temp files persisted (Tempfile cleaned up)
- **API surface parity**: `ChutesHttpClient` gets a new `transcribe_audio` method alongside existing media generation methods

## Acceptance Criteria

- [ ] `/transcribe` command registered in `lib/commands/command_dispatcher.rb`
- [ ] `lib/commands/transcribe_command.rb` created, inheriting from `BaseCommand`
- [ ] `ChutesHttpClient#transcribe_audio` method added to `lib/chutes_http_client.rb`
- [ ] Supports audio via message attachment
- [ ] Supports audio via `--audio <url>` parameter
- [ ] Supports optional `--language <code>` flag
- [ ] Returns transcription text as a bot reply
- [ ] Error handling: missing audio, API failure, file too large
- [ ] Discord audio attachment support added: `lib/discord_server_strategy.rb` extended so `download_attached_images` (rename or supplement) also downloads `audio/*` attachments
- [ ] Help text updated in `lib/commands/help_command.rb`
- [ ] Specs written in `spec/lib/commands/transcribe_command_spec.rb`
- [ ] `standardrb` passes with no violations

## MVP

### lib/commands/transcribe_command.rb

```ruby
class TranscribeCommand < BaseCommand
  def self.parse(prompt)
    text = prompt.to_s.sub(%r{^/transcribe\s*}, "")

    audio = text.match(%r{(?:--audio(?:=|\s+)|-a\s+)((?:https?://[^\s]+)|(?:[^\s]+\.(?:wav|mp3|ogg|flac|m4a|aac)))}i)&.then { _1[1] }
    language = text.match(/(?:--language(?:=|\s+)|-l\s+)([a-z]{2,3})/i)&.then { _1[1] }

    { audio: audio, language: language }.compact
  end

  def execute
    audio_param  = parsed_result[:audio]
    language     = parsed_result[:language]
    has_attached = message["attached_files"]&.any? { |f| audio_file?(f) }

    unless audio_param || has_attached
      server.respond(message, "❌ Please attach an audio file or provide `--audio <url>`.")
      return
    end

    reply = server.respond(message, "🎙️ Transcribing...")

    audio_b64 = if has_attached
      process_audio_file(message["attached_files"].find { |f| audio_file?(f) })
    else
      process_audio_file(audio_param)
    end

    client = ChutesHttpClient.new(nil, ENV["CHUTES_TOKEN"])
    result = client.transcribe_audio({ audio_b64: audio_b64, language: language }.compact)

    server.update(message, reply, result[:text])
  rescue => e
    debug_log("Transcribe error: #{e.message}")
    server.respond(message, "❌ Transcription failed: #{e.message}")
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
      raise "Unknown audio source: #{file_path_or_url}"
    end
    Base64.strict_encode64(convert_to_wav_if_needed(audio_data))
  end

  def convert_to_wav_if_needed(audio_data)
    # (copied from MusicCommand — consider extracting to BaseCommand or a mixin)
    temp_input = Tempfile.new(["audio_input", ".bin"])
    temp_input.binmode
    temp_input.write(audio_data)
    temp_input.close

    format = `ffprobe -v quiet -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "#{temp_input.path}" 2>/dev/null`.strip
    is_wav = %w[pcm_s16le pcm_s24le pcm_s32le].include?(format.downcase)

    result = if is_wav
      audio_data
    else
      temp_output = Tempfile.new(["audio_output", ".wav"])
      temp_output.close
      system("ffmpeg -y -i \"#{temp_input.path}\" -c:a pcm_s16le -ar 44100 \"#{temp_output.path}\" > /dev/null 2>&1")
      data = File.binread(temp_output.path)
      temp_output.unlink
      data
    end

    temp_input.unlink
    raise "Audio too large (max 5 MB)" if result.bytesize > 5 * 1024 * 1024
    result
  end
end
```

### lib/chutes_http_client.rb (addition)

```ruby
def transcribe_audio(payload)
  response = self.class.post(
    "https://chutes-whisper-large-v3.chutes.ai/transcribe",
    body: payload.to_json,
    headers: @default_headers,
    timeout: 300
  )
  raise "Transcription failed: #{response.code} - #{response.body}" unless response.success?
  { text: JSON.parse(response.body)["text"], prompt_id: response.headers["x-chutes-invocationid"] }
end
```

### lib/commands/command_dispatcher.rb (addition)

```ruby
transcribe: {match: %r{^/transcribe(?:\s+([\s\S]*))?}m, class: TranscribeCommand},
```

### spec/lib/commands/transcribe_command_spec.rb

```ruby
require "spec_helper"

RSpec.describe TranscribeCommand do
  let(:server)       { instance_double("MattermostServerStrategy") }
  let(:user_settings){ nil }
  let(:message)      { {"data" => {"post" => {"id" => "p1"}}} }
  let(:parsed_result){ {} }
  let(:command)      { described_class.new(server, message, parsed_result, user_settings, false) }

  describe ".parse" do
    it "parses --language flag" do
      result = described_class.parse("/transcribe --language fr")
      expect(result[:language]).to eq("fr")
    end

    it "parses --audio url" do
      result = described_class.parse("/transcribe --audio https://example.com/audio.mp3")
      expect(result[:audio]).to eq("https://example.com/audio.mp3")
    end

    it "returns empty hash with no args" do
      expect(described_class.parse("/transcribe")).to eq({})
    end
  end

  describe "#execute" do
    it "responds with error when no audio provided" do
      expect(server).to receive(:respond).with(message, /attach an audio file/)
      command.execute
    end

    it "transcribes attached audio file" do
      message["attached_files"] = ["file:///tmp/audio.wav"]
      allow(File).to receive(:binread).and_return("wav_bytes")
      # ... stub ChutesHttpClient and ffprobe/ffmpeg
    end
  end
end
```

## Dependencies & Risks

- **`CHUTES_TOKEN` env var** must be set (already required by MusicCommand/VideoCommand)
- **ffmpeg/ffprobe** must be installed on the host (already a dependency)
- **Audio duplication**: `convert_to_wav_if_needed` and `process_audio_file` are near-identical copies in MusicCommand. Consider extracting to `AudioProcessingMixin` or `BaseCommand` (deferred — keep it simple for now)
- **Discord audio attachments**: Discord strategy currently only downloads image attachments (`lib/discord_server_strategy.rb:130-132`). The `download_attached_images` method (and its private `is_image_attachment?` helper) must be extended to also handle `audio/*` content types. This is included in the acceptance criteria for full cross-platform parity.

### Discord strategy changes

```ruby
# lib/discord_server_strategy.rb

# Rename or supplement download_attached_images → download_attached_files
def download_attached_files(message_data, event)
  return unless event.message.attachments.any?
  message_data["attached_files"] ||= []
  event.message.attachments.each do |attachment|
    next unless is_image_attachment?(attachment) || is_audio_attachment?(attachment)
    message_data["attached_files"] << attachment.url
  end
end

def is_audio_attachment?(attachment)
  attachment.content_type&.start_with?("audio/") || false
end
```

## Sources & References

- Chutes Whisper v3 API docs: https://chutes.ai/docs/guides/modern-audio (payload: `{ audio_b64, language }`, response: `{ text }`)
- Command pattern template: `lib/commands/music_command.rb`
- HTTP client pattern: `lib/chutes_http_client.rb:86-97`
- Command dispatcher: `lib/commands/command_dispatcher.rb:1-17`
- Audio attachment handling (Mattermost): `lib/mattermost_server_strategy.rb:125-165`
- Audio attachment handling (Discord — extended for audio parity): `lib/discord_server_strategy.rb:114-133`
