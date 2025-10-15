require "spec_helper"

RSpec.describe GetDetailsCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:user_settings) { {theme: "dark"} }

  describe "#execute" do
    context "when generation task is found by output filename" do
      let(:parsed_result) { {type: :get_details, image_name: "test_image.png"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }
      let(:task) do
        instance_double(
          "GenerationTask",
          id: 123,
          user_id: "user-123",
          username: "testuser",
          status: "completed",
          workflow_type: "flux",
          prompt_id: "prompt-456",
          output_filename: "test_image.png",
          prompt: "A beautiful landscape",
          parameters: '{"width":1024,"height":1024}',
          exif_data: '{"Make":"Artiste","Model":"Flux"}',
          queued_at: Time.utc(2025, 1, 1, 10, 0, 0),
          started_at: Time.utc(2025, 1, 1, 10, 1, 0),
          completed_at: Time.utc(2025, 1, 1, 10, 2, 30),
          processing_time_seconds: 90.0,
          error_message: nil,
          parsed_parameters: {width: 1024, height: 1024},
          parsed_exif_data: {Make: "Artiste", Model: "Flux"}
        )
      end

      before do
        allow(GenerationTask).to receive(:where).with(output_filename: "test_image.png").and_return([task])
        allow(GenerationTask).to receive(:where).with(prompt_id: "test_image.png").and_return([])
        allow(mattermost).to receive(:respond)
      end

      it "responds with detailed information about the generation task" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🖼️ **Generation Details for:** `test_image.png`")
          expect(response).to include("Task ID: #123")
          expect(response).to include("User: testuser (user-123)")
          expect(response).to include("Status: COMPLETED")
          expect(response).to include("Workflow: flux")
          expect(response).to include("Prompt ID: prompt-456")
          expect(response).to include("A beautiful landscape")
          expect(response).to include('"width": 1024')
          expect(response).to include('"height": 1024')
          expect(response).to include("Make: Artiste")
          expect(response).to include("Model: Flux")
        end

        command.execute
      end
    end

    context "when generation task is found by prompt id" do
      let(:parsed_result) { {type: :get_details, image_name: "prompt-456"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }
      let(:task) do
        instance_double(
          "GenerationTask",
          id: 123,
          user_id: "user-123",
          username: "testuser",
          status: "completed",
          workflow_type: "flux",
          prompt_id: "prompt-456",
          output_filename: "test_image.png",
          prompt: "A beautiful landscape",
          parameters: nil,
          exif_data: "{}",
          queued_at: Time.utc(2025, 1, 1, 10, 0, 0),
          started_at: Time.utc(2025, 1, 1, 10, 1, 0),
          completed_at: Time.utc(2025, 1, 1, 10, 2, 30),
          processing_time_seconds: 90.0,
          error_message: nil,
          parsed_parameters: {},
          parsed_exif_data: {}
        )
      end

      before do
        allow(GenerationTask).to receive(:where).with(output_filename: "prompt-456").and_return([])
        allow(GenerationTask).to receive(:where).with(prompt_id: "prompt-456").and_return([task])
        allow(mattermost).to receive(:respond)
      end

      it "responds with detailed information about the generation task" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("Task ID: #123")
          expect(response).to include("Prompt ID: prompt-456")
        end

        command.execute
      end
    end

    context "when no generation task is found" do
      let(:parsed_result) { {type: :get_details, image_name: "nonexistent.png"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(GenerationTask).to receive(:where).with(output_filename: "nonexistent.png").and_return([])
        allow(GenerationTask).to receive(:where).with(prompt_id: "nonexistent.png").and_return([])
        allow(mattermost).to receive(:respond)
      end

      it "responds with an error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("❌ No generation details found for image: `nonexistent.png`\n\nMake sure you're using the exact filename as it appears in the generated image.")
        end

        command.execute
      end
    end

    context "when generation task has failed status" do
      let(:parsed_result) { {type: :get_details, image_name: "failed_image.png"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }
      let(:task) do
        instance_double(
          "GenerationTask",
          id: 124,
          user_id: "user-123",
          username: "testuser",
          status: "failed",
          workflow_type: "flux",
          prompt_id: "prompt-789",
          output_filename: "failed_image.png",
          prompt: "A beautiful landscape",
          parameters: nil,
          exif_data: "{}",
          queued_at: Time.utc(2025, 1, 1, 10, 0, 0),
          started_at: Time.utc(2025, 1, 1, 10, 1, 0),
          completed_at: Time.utc(2025, 1, 1, 10, 2, 30),
          processing_time_seconds: 90.0,
          error_message: "ComfyUI server error",
          parsed_parameters: {},
          parsed_exif_data: {}
        )
      end

      before do
        allow(GenerationTask).to receive(:where).with(output_filename: "failed_image.png").and_return([task])
        allow(GenerationTask).to receive(:where).with(prompt_id: "failed_image.png").and_return([])
        allow(mattermost).to receive(:respond)
      end

      it "includes error details in the response" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("Error Details:")
          expect(response).to include("ComfyUI server error")
        end

        command.execute
      end
    end

    context "when generation task has no parameters" do
      let(:parsed_result) { {type: :get_details, image_name: "test_image.png"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }
      let(:task) do
        instance_double(
          "GenerationTask",
          id: 123,
          user_id: "user-123",
          username: "testuser",
          status: "completed",
          workflow_type: "flux",
          prompt_id: "prompt-456",
          output_filename: "test_image.png",
          prompt: "A beautiful landscape",
          parameters: nil,
          exif_data: "{}",
          queued_at: Time.utc(2025, 1, 1, 10, 0, 0),
          started_at: Time.utc(2025, 1, 1, 10, 1, 0),
          completed_at: Time.utc(2025, 1, 1, 10, 2, 30),
          processing_time_seconds: 90.0,
          error_message: nil,
          parsed_parameters: {},
          parsed_exif_data: {}
        )
      end

      before do
        allow(GenerationTask).to receive(:where).with(output_filename: "test_image.png").and_return([task])
        allow(GenerationTask).to receive(:where).with(prompt_id: "test_image.png").and_return([])
        allow(mattermost).to receive(:respond)
      end

      it "does not include generation parameters section" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).not_to include("Generation Parameters")
        end

        command.execute
      end
    end

    context "when generation task has no exif data" do
      let(:parsed_result) { {type: :get_details, image_name: "test_image.png"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }
      let(:task) do
        instance_double(
          "GenerationTask",
          id: 123,
          user_id: "user-123",
          username: "testuser",
          status: "completed",
          workflow_type: "flux",
          prompt_id: "prompt-456",
          output_filename: "test_image.png",
          prompt: "A beautiful landscape",
          parameters: nil,
          exif_data: "{}",
          queued_at: Time.utc(2025, 1, 1, 10, 0, 0),
          started_at: Time.utc(2025, 1, 1, 10, 1, 0),
          completed_at: Time.utc(2025, 1, 1, 10, 2, 30),
          processing_time_seconds: 90.0,
          error_message: nil,
          parsed_parameters: {},
          parsed_exif_data: {}
        )
      end

      before do
        allow(GenerationTask).to receive(:where).with(output_filename: "test_image.png").and_return([task])
        allow(GenerationTask).to receive(:where).with(prompt_id: "test_image.png").and_return([])
        allow(mattermost).to receive(:respond)
      end

      it "does not include image metadata section" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).not_to include("Image Metadata")
        end

        command.execute
      end
    end
  end
end
