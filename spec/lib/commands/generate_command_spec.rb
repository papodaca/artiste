require "spec_helper"
require "json"

RSpec.describe GenerateCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:discord) { instance_double("DiscordServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}, "message" => "a beautiful sunset --ar 16:9"} }
  let(:discord_message) { {"user" => double(id: "user-id", username: "testuser"), "message" => "a beautiful sunset --ar 16:9"} }
  let(:parsed_result) { {prompt: "a beautiful sunset", ar: "16:9"} }
  let(:user_settings) { double("UserSettings", user_id: "user-id", username: "testuser", parsed_prompt_params: {model: "flux"}) }
  let(:command) { described_class.new(mattermost, message, parsed_result, user_settings, false) }
  let(:discord_command) { described_class.new(discord, discord_message, parsed_result, user_settings, false) }
  let(:reply) { {"id" => "reply-id"} }
  let(:generation_task) { double("GenerationTask", id: 1, username: "testuser", prompt: "a beautiful sunset", workflow_type: "flux", status: "pending", private: false, file_path: "db/photos/test", output_filename: "test.png", completed_at: Time.now, comfyui_prompt_id: nil) }

  before do
    # Mock PromptParameterParser
    allow(PromptParameterParser).to receive_message_chain(:new, :parse).and_return(parsed_result)
    allow(PromptParameterParser).to receive(:resolve_params).and_return(parsed_result.merge(model: "flux"))

    # Mock GenerationTask
    allow(GenerationTask).to receive(:create).and_return(generation_task)
    allow(generation_task).to receive(:mark_processing)
    allow(generation_task).to receive(:mark_completed)
    allow(generation_task).to receive(:comfyui_prompt_id=)
    allow(generation_task).to receive(:save)
    allow(generation_task).to receive(:set_exif_data)
    allow(generation_task).to receive(:mark_failed)

    # Mock ImageGenerationClient
    mock_image_client = double("ImageGenerationClient")
    allow(ImageGenerationClient).to receive(:create).and_return(mock_image_client)
    allow(mock_image_client).to receive(:is_a?).with(ComfyuiClient).and_return(false)
    allow(mock_image_client).to receive(:generate).and_return({filename: "test.png", image_data: "fake-image-data", prompt_id: "test-prompt-id"})

    # Mock server responses
    allow(mattermost).to receive(:respond).and_return(reply)
    allow(mattermost).to receive(:update)
    allow(discord).to receive(:respond).and_return(reply)
    allow(discord).to receive(:update)

    # Mock file operations
    allow(File).to receive(:write)
    allow(File).to receive(:open).and_return(double("file"))
    allow(Kernel).to receive(:system)

    # Mock exiftool
    allow(Open3).to receive(:capture3).and_return(["{}", "", 0])

    # Mock EM.defer
    allow(EM).to receive(:defer).and_yield
  end

  describe "::parse" do
    it "parses a prompt into a command structure" do
      result = GenerateCommand.parse("a beautiful sunset --ar 16:9")
      expect(result).to include(prompt: "a beautiful sunset", ar: "16:9")
    end

    it "handles parsing errors" do
      allow(PromptParameterParser).to receive_message_chain(:new, :parse).and_return({error: "Invalid parameter"})
      result = GenerateCommand.parse("invalid prompt")
      expect(result).to eq({error: "Invalid parameter"})
    end
  end

  describe "#execute" do
    context "with Mattermost server" do
      before do
        allow(mattermost).to receive(:is_a?).with(MattermostServerStrategy).and_return(true)
        allow(mattermost).to receive(:is_a?).with(DiscordServerStrategy).and_return(false)
      end

      context "when parsed_result has an error" do
        let(:parsed_result) { {error: "Invalid parameter"} }

        it "responds with an error message" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to eq("❌ Invalid parameter")
          end

          command.execute
        end
      end

      context "when prompt is empty" do
        let(:message) { {"data" => {"post" => {"id" => "post-id"}}, "message" => ""} }

        it "responds with an error message" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to eq("Please provide a prompt for image generation!")
          end

          command.execute
        end
      end

      context "when prompt is valid" do
        it "creates a generation task" do
          expect(GenerationTask).to receive(:create).with(
            hash_including(
              prompt: "a beautiful sunset --ar 16:9",
              parameters: a_kind_of(String),
              workflow_type: "flux",
              status: "pending",
              private: false
            )
          )

          command.execute
        end

        it "sends initial response" do
          expect(mattermost).to receive(:respond).with(message, "🎨 Image generation queued...")

          command.execute
        end

        it "generates image using the client" do
          mock_image_client = double("ImageGenerationClient")
          allow(ImageGenerationClient).to receive(:create).and_return(mock_image_client)
          allow(mock_image_client).to receive(:is_a?).with(ComfyuiClient).and_return(false)
          expect(mock_image_client).to receive(:generate).with(hash_including(prompt: "a beautiful sunset", ar: "16:9"))

          command.execute
        end

        it "updates the generation task with completion" do
          expect(generation_task).to receive(:mark_completed).with("test.png")

          command.execute
        end

        it "writes the generated image to file" do
          expect(File).to receive(:write).with("db/photos/test/test.png", "fake-image-data")

          command.execute
        end

        it "updates the server with the generated image" do
          expect(mattermost).to receive(:update).with(
            message,
            reply,
            "🎨 Generating image... This may take a few minutes."
          ).once

          expect(mattermost).to receive(:update).with(
            message,
            reply,
            "🎨 Image generation completed!"
          ).once

          expect(mattermost).to receive(:update).with(
            message,
            reply,
            "",
            anything,
            "db/photos/test/test.png"
          ).once

          command.execute
        end
      end

      context "when using ComfyUI client" do
        before do
          mock_comfyui_client = double("ComfyuiClient")
          allow(ImageGenerationClient).to receive(:create).and_return(mock_comfyui_client)
          allow(mock_comfyui_client).to receive(:is_a?).with(ComfyuiClient).and_return(true)
          allow(mock_comfyui_client).to receive(:generate_and_wait).and_yield(:running, "prompt-id", nil).and_yield(:progress, "prompt-id", [50]).and_return({filename: "test.png", image_data: "fake-image-data", prompt_id: "test-prompt-id"})
        end

        it "handles progress callbacks" do
          expect(generation_task).to receive(:comfyui_prompt_id=).with("prompt-id")
          expect(generation_task).to receive(:save)
          expect(generation_task).to receive(:mark_processing)
          expect(mattermost).to receive(:update).with(message, reply, "🎨 Generating image... This may take a few minutes.")
          expect(mattermost).to receive(:update).with(message, reply, "🎨 Generating image... This may take a few minutes. progressing: 50%.")

          command.execute
        end
      end

      context "when image generation fails" do
        before do
          mock_image_client = double("ImageGenerationClient")
          allow(ImageGenerationClient).to receive(:create).and_return(mock_image_client)
          allow(mock_image_client).to receive(:is_a?).with(ComfyuiClient).and_return(false)
          allow(mock_image_client).to receive(:generate).and_raise(StandardError.new("Generation failed"))
        end

        it "marks the task as failed" do
          expect(generation_task).to receive(:mark_failed).with("Generation failed")

          command.execute
        end

        it "responds with an error message" do
          expect(mattermost).to receive(:update).with(message, reply, "❌ Image generation failed: Generation failed")
          expect(mattermost).to receive(:respond).with(message, /❌ Image generation failed: Generation failed/)

          command.execute
        end
      end
    end

    context "with Discord server" do
      before do
        allow(discord).to receive(:is_a?).with(MattermostServerStrategy).and_return(false)
        allow(discord).to receive(:is_a?).with(DiscordServerStrategy).and_return(true)
      end

      it "extracts user information from Discord message" do
        expect(GenerationTask).to receive(:create).with(
          hash_including(
            user_id: "user-id",
            username: "testuser",
            prompt: "a beautiful sunset --ar 16:9",
            parameters: a_kind_of(String),
            workflow_type: "flux",
            status: "pending",
            private: false
          )
        )

        discord_command.execute
      end
    end
  end
end
