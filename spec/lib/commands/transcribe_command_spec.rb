# frozen_string_literal: true

require "spec_helper"

RSpec.describe TranscribeCommand do
  let(:server) { instance_double("MattermostServerStrategy") }
  let(:user_settings) { instance_double("UserSettings", username: "test_user", user_id: "test-user") }
  let(:message) do
    double("Message").tap do |msg|
      allow(msg).to receive(:[]).with("attached_files").and_return(nil)
      allow(msg).to receive(:[]=)
    end
  end

  before do
    allow(server).to receive(:respond).and_return({"id" => "reply-id"})
    allow(server).to receive(:update)
  end

  describe ".parse" do
    it "parses --language flag" do
      result = described_class.parse("/transcribe --language fr")
      expect(result[:language]).to eq("fr")
    end

    it "parses -l shorthand for language" do
      result = described_class.parse("/transcribe -l en")
      expect(result[:language]).to eq("en")
    end

    it "parses --audio url" do
      result = described_class.parse("/transcribe --audio https://example.com/audio.mp3")
      expect(result[:audio]).to eq("https://example.com/audio.mp3")
    end

    it "parses -a shorthand for audio" do
      result = described_class.parse("/transcribe -a https://example.com/audio.wav")
      expect(result[:audio]).to eq("https://example.com/audio.wav")
    end

    it "parses both audio and language" do
      result = described_class.parse("/transcribe --audio https://example.com/audio.mp3 --language en")
      expect(result[:audio]).to eq("https://example.com/audio.mp3")
      expect(result[:language]).to eq("en")
    end

    it "returns empty hash when called with no args" do
      expect(described_class.parse("/transcribe")).to eq({})
    end

    it "returns empty hash for whitespace-only input" do
      expect(described_class.parse("/transcribe   ")).to eq({})
    end
  end

  describe "#execute" do
    context "when no audio is provided" do
      let(:parsed_result) { {} }
      let(:command) { described_class.new(server, message, parsed_result, user_settings) }

      it "responds with an error message" do
        command.execute
        expect(server).to have_received(:respond).with(message, a_string_matching(/attach an audio file/))
      end

      it "does not attempt transcription" do
        expect(ChutesHttpClient).not_to receive(:new)
        command.execute
      end
    end

    context "when audio URL is provided via --audio" do
      let(:parsed_result) { {audio: "https://example.com/audio.mp3"} }
      let(:command) { described_class.new(server, message, parsed_result, user_settings) }
      let(:mock_client) { instance_double("ChutesHttpClient") }

      before do
        allow(ChutesHttpClient).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:transcribe_audio).and_return(
          {text: "Hello world", prompt_id: "abc123"}
        )
        # Stub HTTP and audio processing
        allow(HTTParty).to receive(:get).and_return(double("Response", body: "audio_bytes"))
        allow(command).to receive(:convert_to_wav_if_needed).and_return("wav_bytes")
        allow(Base64).to receive(:strict_encode64).and_return("base64audio")
      end

      it "sends a processing message first" do
        command.execute
        expect(server).to have_received(:respond).with(message, /Transcribing/)
      end

      it "calls transcribe_audio with base64 audio" do
        command.execute
        expect(mock_client).to have_received(:transcribe_audio).with(
          hash_including(audio_b64: "base64audio")
        )
      end

      it "updates the reply with the transcription text" do
        command.execute
        expect(server).to have_received(:update).with(message, {"id" => "reply-id"}, "Hello world")
      end

      it "includes language in payload when specified" do
        parsed_result[:language] = "fr"
        command.execute
        expect(mock_client).to have_received(:transcribe_audio).with(
          hash_including(audio_b64: "base64audio", language: "fr")
        )
      end
    end

    context "when an audio file is attached to the message" do
      let(:parsed_result) { {} }
      let(:command) { described_class.new(server, message, parsed_result, user_settings) }
      let(:mock_client) { instance_double("ChutesHttpClient") }

      before do
        allow(message).to receive(:[]).with("attached_files").and_return(["file:///tmp/audio.wav"])
        allow(ChutesHttpClient).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:transcribe_audio).and_return(
          {text: "Transcribed text", prompt_id: "xyz789"}
        )
        allow(File).to receive(:binread).and_return("wav_bytes")
        allow(command).to receive(:convert_to_wav_if_needed).and_return("wav_bytes")
        allow(Base64).to receive(:strict_encode64).and_return("base64audio")
      end

      it "uses the attached file for transcription" do
        command.execute
        expect(mock_client).to have_received(:transcribe_audio).with(
          hash_including(audio_b64: "base64audio")
        )
      end

      it "updates reply with transcription" do
        command.execute
        expect(server).to have_received(:update).with(message, {"id" => "reply-id"}, "Transcribed text")
      end
    end

    context "when the API raises an error" do
      let(:parsed_result) { {audio: "https://example.com/audio.mp3"} }
      let(:command) { described_class.new(server, message, parsed_result, user_settings) }
      let(:mock_client) { instance_double("ChutesHttpClient") }

      before do
        allow(ChutesHttpClient).to receive(:new).and_return(mock_client)
        allow(mock_client).to receive(:transcribe_audio).and_raise("API error: 500")
        allow(HTTParty).to receive(:get).and_return(double("Response", body: "audio_bytes"))
        allow(command).to receive(:convert_to_wav_if_needed).and_return("wav_bytes")
        allow(Base64).to receive(:strict_encode64).and_return("base64audio")
      end

      it "updates the reply with an error message" do
        command.execute
        expect(server).to have_received(:update).with(message, {"id" => "reply-id"},
          /Transcription failed.*API error/)
      end
    end
  end

  describe "#convert_to_wav_if_needed" do
    let(:command) { described_class.new(server, message, {}, user_settings) }

    before do
      allow(command).to receive(:`).with(/ffprobe/).and_return("pcm_s16le")
    end

    context "when audio exceeds 5 MB" do
      it "raises a file size error" do
        large_audio = "x" * (6 * 1024 * 1024)
        expect do
          command.send(:convert_to_wav_if_needed, large_audio)
        end.to raise_error(/Audio file is too large.*Maximum allowed size is 5 MB/)
      end
    end

    context "when audio is within 5 MB" do
      it "does not raise an error" do
        small_audio = "x" * (1 * 1024 * 1024)
        expect do
          command.send(:convert_to_wav_if_needed, small_audio)
        end.not_to raise_error
      end
    end
  end

  describe "command dispatcher registration" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/transcribe --language en")
      expect(result[:type]).to eq(:transcribe)
      expect(result[:language]).to eq("en")
    end

    it "is registered for plain /transcribe with no args" do
      result = CommandDispatcher.parse_command("/transcribe")
      expect(result[:type]).to eq(:transcribe)
    end
  end
end
