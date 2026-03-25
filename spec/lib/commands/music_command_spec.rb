require "spec_helper"
require_relative "../../../config/database"

RSpec.describe MusicCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) do
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}).tap do |msg|
      allow(msg).to receive(:[]).with("attached_files").and_return(nil)
    end
  end
  let(:user_settings) { instance_double("UserSettings", username: "test_user", user_id: "test-user") }

  before do
    allow(mattermost).to receive(:respond)
    allow(mattermost).to receive(:update)
  end

  describe ".parse" do
    it "extracts style prompt before lyrics flag" do
      result = described_class.parse("/music upbeat electronic -l la la la --duration 60")
      expect(result[:style_prompt]).to eq("upbeat electronic")
      expect(result[:lyrics]).to eq("la la la")
      expect(result[:duration]).to eq(60)
    end

    it "handles style prompt without lyrics" do
      result = described_class.parse("/music ambient piano --duration 120")
      expect(result[:style_prompt]).to eq("ambient piano")
      expect(result[:lyrics]).to be_nil
    end

    it "parses audio parameter" do
      result = described_class.parse("/music --audio https://example.com/audio.mp3")
      expect(result[:audio]).to eq("https://example.com/audio.mp3")
    end

    it "parses all music parameters" do
      result = described_class.parse("/music jazz -l scat --duration 180 --cfg 5.0 --steps 50 --scheduler midpoint --batch 2 --seed 42")
      expect(result[:style_prompt]).to eq("jazz")
      expect(result[:lyrics]).to eq("scat")
      expect(result[:duration]).to eq(180)
      expect(result[:cfg]).to eq(5.0)
      expect(result[:steps]).to eq(50)
      expect(result[:scheduler]).to eq("midpoint")
      expect(result[:batch]).to eq(2)
      expect(result[:seed]).to eq(42)
    end

    it "parses multiline lyrics" do
      result = described_class.parse("/music jazz -l line one\nline two\nline three --duration 60")
      expect(result[:style_prompt]).to eq("jazz")
      expect(result[:lyrics]).to eq("line one\nline two\nline three")
      expect(result[:duration]).to eq(60)
    end

    it "parses lyrics at end of prompt" do
      result = described_class.parse("/music jazz -l these are the lyrics")
      expect(result[:style_prompt]).to eq("jazz")
      expect(result[:lyrics]).to eq("these are the lyrics")
    end
  end

  describe "#execute" do
    context "when no style prompt or audio provided" do
      let(:parsed_result) { {style_prompt: "", lyrics: nil, audio: nil} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "returns an error message" do
        command.execute
        expect(mattermost).to have_received(:respond).with(message,
          a_string_matching(/provide either a style prompt or an audio file/))
      end
    end

    context "when duration is out of range" do
      let(:parsed_result) { {style_prompt: "test", lyrics: nil, duration: 300} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "returns an error message" do
        command.execute
        expect(mattermost).to have_received(:respond).with(message,
          a_string_matching(/Duration must be between 15 and 285/))
      end
    end

    context "when batch size is out of range" do
      let(:parsed_result) { {style_prompt: "test", lyrics: nil, batch: 5} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "returns an error message" do
        command.execute
        expect(mattermost).to have_received(:respond).with(message,
          a_string_matching(/Batch size must be between 1 and 4/))
      end
    end

    context "when audio is too short" do
      let(:parsed_result) { {style_prompt: "test", lyrics: nil, duration: 10} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "returns an error message" do
        command.execute
        expect(mattermost).to have_received(:respond).with(message,
          a_string_matching(/Duration must be between 15 and 285/))
      end
    end
  end

  describe "#convert_to_wav_if_needed" do
    let(:command) { described_class.new(mattermost, message, {}, user_settings) }

    before do
      allow(command).to receive(:`).with(/ffprobe/).and_return("pcm_s16le")
    end

    context "when audio file is larger than 5MB" do
      it "raises an error about file size" do
        large_audio_data = "x" * (6 * 1024 * 1024)
        expect do
          command.send(:convert_to_wav_if_needed, large_audio_data)
        end.to raise_error(/Audio file is too large.*Maximum allowed size is 5 MB/)
      end
    end

    context "when audio file is smaller than 5MB" do
      it "does not raise an error" do
        small_audio_data = "x" * (1 * 1024 * 1024)
        expect do
          command.send(:convert_to_wav_if_needed, small_audio_data)
        end.not_to raise_error
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/music upbeat electronic --duration 60")
      expect(result[:type]).to eq(:music)
      expect(result[:style_prompt]).to eq("upbeat electronic")
      expect(result[:duration]).to eq(60)
    end
  end

  describe "album art generation" do
    let(:style_prompt) { "ambient electronic" }
    let(:parsed_result) do
      {
        type: :music,
        style_prompt: style_prompt,
        duration: 30
      }
    end
    let(:task) do
      instance_double("GenerationTask",
        id: 1,
        output_filename: "chutes_123.m4a",
        completed_at: Time.now,
        to_h: {id: 1, output_filename: "chutes_123.m4a"})
    end
    let(:temp_wav) { instance_double("Tempfile") }
    let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

    before do
      allow(command).to receive(:debug)
      allow(GenerationTask).to receive(:create).and_return(task)
      allow(task).to receive(:mark_processing)
      allow(task).to receive(:mark_completed)
      allow(command).to receive(:music_file_path).and_return("/tmp/music/2026/03/21")
      allow(FileUtils).to receive(:mkdir_p)
      allow(Tempfile).to receive(:new).with(["music", ".wav"]).and_return(temp_wav)
      allow(temp_wav).to receive(:binmode)
      allow(temp_wav).to receive(:write)
      allow(temp_wav).to receive(:close)
      allow(temp_wav).to receive(:unlink)
      allow(temp_wav).to receive(:path).and_return("/tmp/music.wav")
      allow(Kernel).to receive(:system).and_return(true)
      allow(PhotoGalleryWebSocket).to receive(:notify_new_photo)
      allow(File).to receive(:binwrite)
    end

    it "generates album art with the correct prompt" do
      mock_http_client = instance_double("ChutesHttpClient")
      allow(ChutesHttpClient).to receive(:new).and_return(mock_http_client)

      allow(mock_http_client).to receive(:generate_music).and_return(
        {audio_data: "fake wav data", prompt_id: "music-123"}
      )

      allow(mock_http_client).to receive(:generate_image).with(
        hash_including(
          prompt: "flat abstract album cover for this style of music: #{style_prompt}",
          width: 1024,
          height: 1024
        ),
        model: "z-image"
      ).and_return(
        {image_data: "fake png data", prompt_id: "image-123"}
      )

      allow(mattermost).to receive(:respond).and_return({id: "reply-id"})
      allow(mattermost).to receive(:update)
      allow(File).to receive(:open).and_return(StringIO.new("fake m4a data"))

      command.execute

      expect(mock_http_client).to have_received(:generate_image).with(
        hash_including(
          prompt: "flat abstract album cover for this style of music: #{style_prompt}",
          width: 1024,
          height: 1024
        ),
        model: "z-image"
      )
    end

    it "continues if album art generation fails" do
      mock_http_client = instance_double("ChutesHttpClient")
      allow(ChutesHttpClient).to receive(:new).and_return(mock_http_client)

      allow(mock_http_client).to receive(:generate_music).and_return(
        {audio_data: "fake wav data", prompt_id: "music-123"}
      )

      allow(mock_http_client).to receive(:generate_image).and_raise("Image generation failed")

      allow(mattermost).to receive(:respond).and_return({id: "reply-id"})
      allow(mattermost).to receive(:update)
      allow(File).to receive(:open).and_return(StringIO.new("fake m4a data"))

      command.execute

      expect(mock_http_client).to have_received(:generate_music)
      expect(mattermost).to have_received(:update).with(message, anything, anything, anything, anything)
    end
  end
end
