require "spec_helper"
require "json"

RSpec.describe VideoCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:parsed_result) { {resolution: "832*480", seed: 42, steps: 25, frames: 81, guidance_scale: 5, negative_prompt: "test negative prompt", prompt: "A beautiful landscape"} }
  let(:user_settings) { nil }
  let(:command) { described_class.new(mattermost, message, parsed_result, user_settings, false) }
  let(:reply) { {"id" => "reply-id"} }

  before do
    # Set environment variables for testing
    ENV["CHUTES_API_TOKEN"] = "test-api-token"
  end

  after do
    # Clean up environment variables
    ENV.delete("CHUTES_API_TOKEN")
  end

  describe "::select_resolution_by_aspect_ratio" do
    it "returns 16:9 resolution for 16:9 aspect ratio" do
      result = VideoCommand.select_resolution_by_aspect_ratio(16.0 / 9.0)
      expect(result).to eq("1280*720")
    end

    it "returns 9:16 resolution for 9:16 aspect ratio" do
      result = VideoCommand.select_resolution_by_aspect_ratio(9.0 / 16.0)
      expect(result).to eq("720*1280")
    end

    it "returns square resolution for 1:1 aspect ratio" do
      result = VideoCommand.select_resolution_by_aspect_ratio(1.0)
      expect(result).to eq("1024*1024")
    end

    it "returns widescreen resolution for aspect ratios wider than 16:9" do
      result = VideoCommand.select_resolution_by_aspect_ratio(2.0) # 2:1 is wider than 16:9
      expect(result).to eq("832*480")
    end

    it "returns portrait resolution for aspect ratios taller than 9:16" do
      result = VideoCommand.select_resolution_by_aspect_ratio(0.4) # Taller than 9:16
      expect(result).to eq("480*832")
    end

    it "handles aspect ratios within tolerance" do
      # Test with values slightly off from exact ratios but within tolerance
      result = VideoCommand.select_resolution_by_aspect_ratio(1.7) # Close to 16:9 (1.777...)
      expect(result).to eq("1280*720")
    end
  end

  describe "::parse_aspect_ratio" do
    it "parses 16:9 aspect ratio correctly" do
      result = VideoCommand.parse_aspect_ratio("16:9")
      expect(result).to eq(16.0 / 9.0)
    end

    it "parses 9:16 aspect ratio correctly" do
      result = VideoCommand.parse_aspect_ratio("9:16")
      expect(result).to eq(9.0 / 16.0)
    end

    it "parses 1:1 aspect ratio correctly" do
      result = VideoCommand.parse_aspect_ratio("1:1")
      expect(result).to eq(1.0)
    end

    it "parses 4:3 aspect ratio correctly" do
      result = VideoCommand.parse_aspect_ratio("4:3")
      expect(result).to eq(4.0 / 3.0)
    end

    it "returns 1.0 for invalid format" do
      result = VideoCommand.parse_aspect_ratio("invalid")
      expect(result).to eq(1.0)
    end

    it "returns 1.0 for single number" do
      result = VideoCommand.parse_aspect_ratio("16")
      expect(result).to eq(1.0)
    end

    it "returns 1.0 for empty string" do
      result = VideoCommand.parse_aspect_ratio("")
      expect(result).to eq(1.0)
    end
  end

  describe "::parse" do
    before do
      # Mock the PromptParameterParser to return consistent results for testing
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })
    end

    it "parses a prompt into a command structure" do
      result = VideoCommand.parse("A beautiful landscape")

      # Check that the result has the expected structure
      expect(result).to include(:prompt, :resolution, :seed, :steps, :frames, :guidance, :negative_prompt)
      expect(result[:prompt]).to eq("A beautiful landscape")
      expect(result[:resolution]).to eq("1024*1024") # Default for 1:1 aspect ratio
      expect(result[:seed]).to eq(42)
      expect(result[:steps]).to eq(25)
      expect(result[:frames]).to be_nil
      expect(result[:guidance]).to be_nil
      expect(result[:negative_prompt]).to eq("")
    end

    it "parses frames from prompt" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape --frames 100",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape --frames 100")
      expect(result[:frames]).to eq(100)
      expect(result[:prompt]).to eq("A beautiful landscape")
    end

    it "parses guidance scale from prompt" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape --guidance 7.5",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape --guidance 7.5")
      expect(result[:guidance]).to eq(7.5)
      expect(result[:prompt]).to eq("A beautiful landscape")
    end

    it "parses short form frames flag" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape -f 50",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape -f 50")
      expect(result[:frames]).to eq(50)
      expect(result[:prompt]).to eq("A beautiful landscape")
    end

    it "parses short form guidance flag" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape -g 3.5",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape -g 3.5")
      expect(result[:guidance]).to eq(3.5)
      expect(result[:prompt]).to eq("A beautiful landscape")
    end

    it "selects 16:9 resolution for 16:9 aspect ratio" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: "16:9",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape")
      expect(result[:resolution]).to eq("1280*720")
    end

    it "selects 9:16 resolution for 9:16 aspect ratio" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: "9:16",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape")
      expect(result[:resolution]).to eq("720*1280")
    end

    it "selects square resolution for 1:1 aspect ratio" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape")
      expect(result[:resolution]).to eq("1024*1024")
    end

    it "selects widescreen resolution for aspect ratios wider than 16:9" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: "21:9",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape")
      expect(result[:resolution]).to eq("832*480")
    end

    it "selects portrait resolution for aspect ratios taller than 9:16" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: "9:21",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape")
      expect(result[:resolution]).to eq("480*832")
    end

    it "defaults to square resolution when no aspect ratio is specified" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape",
        aspect_ratio: nil,
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape")
      expect(result[:resolution]).to eq("1024*1024")
    end

    it "strips frames and guidance flags from prompt" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape --frames 100 --guidance 7.5",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape --frames 100 --guidance 7.5")
      expect(result[:prompt]).to eq("A beautiful landscape")
      expect(result[:frames]).to eq(100)
      expect(result[:guidance]).to eq(7.5)
    end

    it "strips short form frames and guidance flags from prompt" do
      allow(PromptParameterParser).to receive(:parse).and_return({
        prompt: "A beautiful landscape -f 50 -g 3.5",
        aspect_ratio: "1:1",
        seed: 42,
        steps: 25,
        negative_prompt: ""
      })

      result = VideoCommand.parse("A beautiful landscape -f 50 -g 3.5")
      expect(result[:prompt]).to eq("A beautiful landscape")
      expect(result[:frames]).to eq(50)
      expect(result[:guidance]).to eq(3.5)
    end
  end

  describe "#execute" do
    context "when prompt is provided" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        allow(mattermost).to receive(:update)
      end

      it "calls the Chutes API and responds with the generated video" do
        # Mock the Chutes HTTP client
        mock_http_client = instance_double("ChutesHttpClient")
        allow(ChutesHttpClient).to receive(:new).and_return(mock_http_client)

        # Mock the video generation response
        mock_video_data = "mock video data"
        allow(mock_http_client).to receive(:generate_video).and_return({
          video_data: mock_video_data,
          prompt_id: "test-prompt-id"
        })

        # Mock Tempfile
        mock_tempfile = double("Tempfile")
        allow(Tempfile).to receive(:new).and_return(mock_tempfile)
        allow(mock_tempfile).to receive(:binmode)
        allow(mock_tempfile).to receive(:write)
        allow(mock_tempfile).to receive(:flush)
        allow(mock_tempfile).to receive(:close)
        allow(mock_tempfile).to receive(:unlink)
        allow(mock_tempfile).to receive(:path).and_return("/tmp/video123.mp4")

        # Mock FileUtils
        allow(FileUtils).to receive(:mkdir_p)
        allow(FileUtils).to receive(:cp)

        # Mock File.open to return a file-like object
        mock_file = double("File")
        allow(File).to receive(:open).and_return(mock_file)

        # Mock the generation task
        mock_generation_task = double("GenerationTask")
        allow(mock_generation_task).to receive(:id).and_return(123)
        allow(mock_generation_task).to receive(:file_path).and_return("db/photos/2025/09/28")
        allow(mock_generation_task).to receive(:output_filename).and_return("chutes_1759102469.mp4")
        allow(mock_generation_task).to receive(:processing_time_seconds).and_return(1.5)
        allow(mock_generation_task).to receive(:username).and_return("test_user")
        allow(mock_generation_task).to receive(:workflow_type).and_return("video-generation")
        allow(mock_generation_task).to receive(:completed_at).and_return(Time.now)
        allow(mock_generation_task).to receive(:prompt).and_return("A beautiful landscape")
        allow(GenerationTask).to receive(:create).and_return(mock_generation_task)
        allow(mock_generation_task).to receive(:private=)
        allow(mock_generation_task).to receive(:save)
        allow(mock_generation_task).to receive(:mark_processing)
        allow(mock_generation_task).to receive(:mark_completed)

        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "🎬 Generating video...").and_return(reply)

        # Expect the processing update
        expect(mattermost).to receive(:update).with(message, reply, "🎬 Generating video... (processing)")

        # Expect the uploading update
        expect(mattermost).to receive(:update).with(message, reply, "✅ Video generated! Uploading...")

        # Expect the final update call with file (this is how the actual implementation works)
        expect(mattermost).to receive(:update).with(
          message,
          reply,
          "", # debug_log_enabled is false in the test
          mock_file,
          "chutes_1759102469.mp4"
        )

        command.execute
      end
    end

    context "when prompt is empty" do
      let(:parsed_result) { {resolution: "832*480", seed: 42, steps: 25, frames: 81, guidance: 5, negative_prompt: "test negative prompt", prompt: ""} }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with an error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("❌ Please provide a prompt for the video command.")
        end

        command.execute
      end
    end

    context "when prompt is nil" do
      let(:parsed_result) { {resolution: "832*480", seed: 42, steps: 25, frames: 81, guidance: 5, negative_prompt: "test negative prompt", prompt: nil} }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with an error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("❌ Please provide a prompt for the video command.")
        end

        command.execute
      end
    end

    context "when API request fails with an error response" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        allow(mattermost).to receive(:update)
      end

      it "responds with an error message" do
        # Mock the Chutes HTTP client
        mock_http_client = instance_double("ChutesHttpClient")
        allow(ChutesHttpClient).to receive(:new).and_return(mock_http_client)

        # Mock the video generation to raise an error
        allow(mock_http_client).to receive(:generate_video).and_raise("Failed to generate video")

        # Mock the generation task
        mock_generation_task = double("GenerationTask")
        allow(mock_generation_task).to receive(:id).and_return(123)
        allow(mock_generation_task).to receive(:file_path).and_return("db/photos/2025/09/28")
        allow(mock_generation_task).to receive(:output_filename).and_return("chutes_1759102469.mp4")
        allow(mock_generation_task).to receive(:username).and_return("test_user")
        allow(mock_generation_task).to receive(:workflow_type).and_return("video-generation")
        allow(mock_generation_task).to receive(:completed_at).and_return(Time.now)
        allow(mock_generation_task).to receive(:prompt).and_return("A beautiful landscape")
        allow(GenerationTask).to receive(:create).and_return(mock_generation_task)
        allow(mock_generation_task).to receive(:private=)
        allow(mock_generation_task).to receive(:save)
        allow(mock_generation_task).to receive(:mark_processing)
        allow(mock_generation_task).to receive(:mark_failed)

        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "🎬 Generating video...").and_return(reply)

        # Expect the error response
        expect(mattermost).to receive(:update).with(message, reply, "❌ Sorry, I encountered an error while generating the video: Failed to generate video")

        command.execute
      end
    end

    context "when API token is not configured" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        allow(mattermost).to receive(:update)
        ENV.delete("CHUTES_API_TOKEN")
      end

      it "responds with an error message" do
        # Mock the generation task
        mock_generation_task = double("GenerationTask")
        allow(mock_generation_task).to receive(:id).and_return(123)
        allow(mock_generation_task).to receive(:file_path).and_return("db/photos/2025/09/28")
        allow(mock_generation_task).to receive(:output_filename).and_return("chutes_1759102469.mp4")
        allow(mock_generation_task).to receive(:username).and_return("test_user")
        allow(mock_generation_task).to receive(:workflow_type).and_return("video-generation")
        allow(mock_generation_task).to receive(:completed_at).and_return(Time.now)
        allow(mock_generation_task).to receive(:prompt).and_return("A beautiful landscape")
        allow(GenerationTask).to receive(:create).and_return(mock_generation_task)
        allow(mock_generation_task).to receive(:private=)
        allow(mock_generation_task).to receive(:save)
        allow(mock_generation_task).to receive(:mark_failed)

        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "🎬 Generating video...").and_return(reply)

        # Expect the error response
        expect(mattermost).to receive(:update).with(message, reply, "❌ Sorry, I encountered an error while generating the video: Chutes API token is not configured. Please set the CHUTES_API_TOKEN environment variable.")

        command.execute
      end
    end
  end
end
