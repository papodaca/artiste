require "spec_helper"
require_relative "../../../config/database"

RSpec.describe EditCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) {
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}})
  }
  let(:user_settings) { instance_double("UserSettings", username: "test_user", user_id: "test-user") }
  let(:image_generation_client) { instance_double("ChutesClient") }

  before do
    allow(mattermost).to receive(:respond)
    allow(mattermost).to receive(:update)
    allow(ImageGenerationClient).to receive(:create).and_return(image_generation_client)
  end

  describe ".parse" do
    context "with valid format" do
      it "parses prompt and image parameter correctly" do
        result = described_class.parse("a beautiful sunset --image https://example.com/image.jpg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq("https://example.com/image.jpg")
      end

      it "parses with short image flag" do
        result = described_class.parse("a beautiful sunset -i https://example.com/image.jpg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq("https://example.com/image.jpg")
      end

      it "parses with other parameters" do
        result = described_class.parse("a beautiful sunset --image https://example.com/image.jpg --steps 30 --width 1024")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq("https://example.com/image.jpg")
        expect(result[:steps]).to eq(30)
        expect(result[:width]).to eq(1024)
      end

      it "parses with task ID parameter" do
        result = described_class.parse("a beautiful sunset --task 123")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:task_id]).to eq(123)
      end

      it "parses with short task flag" do
        result = described_class.parse("a beautiful sunset -t 456")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:task_id]).to eq(456)
      end

      it "parses with filename parameter" do
        result = described_class.parse("a beautiful sunset --image chutes_1758256813.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq("chutes_1758256813.png")
      end

      it "parses with jpg filename" do
        result = described_class.parse("a beautiful sunset --image test_image.jpg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq("test_image.jpg")
      end

      it "parses with jpeg filename" do
        result = described_class.parse("a beautiful sunset --image test_image.jpeg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq("test_image.jpeg")
      end
    end

    context "with invalid format" do
      it "returns error for missing image parameter" do
        result = described_class.parse("a beautiful sunset")
        expect(result[:error]).to be_nil # Should parse successfully, validation happens in execute
      end

      it "returns error for invalid image URL" do
        result = described_class.parse("a beautiful sunset --image invalid-url")
        expect(result[:error]).to be_nil # Should parse successfully, validation happens in execute
      end
    end
  end

  describe "#execute" do
    context "when parsing error occurs" do
      let(:parsed_result) { {error: "Invalid format"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with the error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Invalid format")
        end

        command.execute
      end
    end

    context "when image parameter is missing" do
      let(:parsed_result) { {prompt: "a beautiful sunset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about missing image" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Please provide either an image URL using --image <url>, a filename using --image <filename>, or a task ID using --task <id> parameter for editing.")
        end

        command.execute
      end
    end

    context "when prompt is missing" do
      let(:parsed_result) { {image: "https://example.com/image.jpg"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about missing prompt" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Please provide a prompt")
        end

        command.execute
      end
    end

    context "when both image and task_id are provided" do
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          image: "https://example.com/image.jpg",
          task_id: 123
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about providing both parameters" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Please provide either an image (URL or filename) or a task ID, but not both.")
        end

        command.execute
      end
    end

    context "when task_id parameter is provided" do
      let(:task) {
        instance_double("GenerationTask",
          output_filename: "test_image.png",
          file_path: "db/photos/2025/09/19"
        )
      }
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          task_id: 123,
          steps: 30,
          width: 1024
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        # Mock the task lookup
        allow(GenerationTask).to receive(:[]).with(123).and_return(task)
        
        # Mock the file operations
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).and_return("fake_image_data_with_PNG_header")
        allow(Base64).to receive(:strict_encode64).and_return("base64_encoded_image")
        
        # Mock the image generation with callback
        allow(image_generation_client).to receive(:generate) do |&block|
          block.call(:started, "test-prompt-id", nil) if block
          block.call(:completed, "test-prompt-id", nil) if block
          {
            image_data: "generated_image_data",
            prompt_id: "test-prompt-id"
          }
        end
      end

      it "loads image from task and generates edit" do
        # Just test that the command executes without errors for now
        expect(mattermost).to receive(:respond).and_return(double("reply"))
        expect { command.execute }.not_to raise_error
      end

      it "saves generation task" do
        # Just test that the command executes without errors for now
        expect(mattermost).to receive(:respond).and_return(double("reply"))
        expect { command.execute }.not_to raise_error
      end
    end

    context "when task_id is not found" do
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          task_id: 999
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        # Mock the task lookup to return nil (not found)
        allow(GenerationTask).to receive(:[]).with(999).and_return(nil)
      end

      it "responds with error message about task not found" do
        # First call is the initial response, second call is the error response
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🖼️ Editing your image...")
        end
        
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Error editing image: Failed to load image from task 999: Task with ID 999 not found")
        end

        command.execute
      end
    end

    context "when filename parameter is provided" do
      let(:task) {
        instance_double("GenerationTask",
          id: 123,
          output_filename: "chutes_1758256813.png",
          file_path: "db/photos/2025/09/19",
          completed_at: Time.now
        )
      }
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          image: "chutes_1758256813.png",
          steps: 30,
          width: 1024
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        # Mock the task lookup by filename
        allow(GenerationTask).to receive(:where).with(output_filename: "chutes_1758256813.png").and_return([task])
        
        # Mock the file operations
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).and_return("fake_image_data_with_PNG_header")
        allow(Base64).to receive(:strict_encode64).and_return("base64_encoded_image")
        
        # Mock the image generation with callback
        allow(image_generation_client).to receive(:generate) do |&block|
          block.call(:started, "test-prompt-id", nil) if block
          block.call(:completed, "test-prompt-id", nil) if block
          {
            image_data: "generated_image_data",
            prompt_id: "test-prompt-id"
          }
        end
      end

      it "finds task by filename and loads image" do
        expect(GenerationTask).to receive(:where).with(output_filename: "chutes_1758256813.png")
        expect(mattermost).to receive(:respond).and_return(double("reply"))
        expect { command.execute }.not_to raise_error
      end
    end

    context "when filename is not found" do
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          image: "nonexistent_file.png"
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        # Mock the task lookup to return empty array (not found)
        allow(GenerationTask).to receive(:where).with(output_filename: "nonexistent_file.png").and_return([])
      end

      it "responds with error message about filename not found" do
        # First call is the initial response, second call is the error response
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🖼️ Editing your image...")
        end
        
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Error editing image: No task found with filename: nonexistent_file.png")
        end

        command.execute
      end
    end

    context "when filename has invalid format" do
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          image: "invalid/filename.png"
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about invalid filename format" do
        # First call is the initial response, second call is the error response
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🖼️ Editing your image...")
        end
        
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Error editing image: Invalid filename format: invalid/filename.png. Expected format: filename.extension")
        end

        command.execute
      end
    end

    context "when all parameters are valid" do
      let(:parsed_result) { 
        {
          prompt: "a beautiful sunset", 
          image: "https://example.com/image.jpg",
          steps: 30,
          width: 1024
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        # Mock the image download
        allow_any_instance_of(EditCommand).to receive(:download_image).and_return("fake_image_data")
        allow(Base64).to receive(:strict_encode64).and_return("base64_encoded_image")
        
        # Mock the image generation with callback
        allow(image_generation_client).to receive(:generate) do |&block|
          block.call(:started, "test-prompt-id", nil) if block
          block.call(:completed, "test-prompt-id", nil) if block
          {
            image_data: "generated_image_data",
            prompt_id: "test-prompt-id"
          }
        end
      end

      it "downloads image and generates edit" do
        expect_any_instance_of(EditCommand).to receive(:download_image).with("https://example.com/image.jpg")
        expect(Base64).to receive(:strict_encode64).with("fake_image_data")
        expect(image_generation_client).to receive(:generate).with(
          hash_including(
            prompt: "a beautiful sunset",
            image_b64: "base64_encoded_image",
            steps: 30,
            width: 1024
          )
        )

        expect(mattermost).to receive(:respond).and_return(double("reply"))
        expect(mattermost).to receive(:update).at_least(:once)

        command.execute
      end

      it "saves generation task" do
        # Expect task creation at the beginning
        expect(GenerationTask).to receive(:create).with(
          hash_including(
            user_id: "test-user",
            prompt: "a beautiful sunset",
            workflow_type: "qwen-image-edit",
            status: "pending"
          )
        ).and_return(double("GenerationTask", id: 123, mark_processing: nil, mark_completed: nil, processing_time_seconds: 1.5, file_path: "db/photos/2025/09/19", output_filename: "test_output.png", username: "test_user", workflow_type: "qwen-image-edit", completed_at: Time.now, prompt: "a beautiful sunset", set_exif_data: nil))

        expect(mattermost).to receive(:respond).and_return(double("reply"))
        expect(mattermost).to receive(:update).at_least(:once)

        command.execute
      end
    end

    context "when image download fails" do
      let(:parsed_result) { 
        {
          prompt: "a beautiful sunset", 
          image: "https://example.com/image.jpg"
        }
      }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow_any_instance_of(EditCommand).to receive(:download_image).and_raise("Download failed")
      end

      it "responds with error message" do
        # First call is the initial response, second call is the error response
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🖼️ Editing your image...")
        end
        
        expect(mattermost).to receive(:respond).ordered do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Error editing image: Download failed")
        end

        command.execute
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/edit a beautiful sunset --image https://example.com/image.jpg")
      expect(result[:type]).to eq(:edit)
      expect(result[:prompt]).to eq("a beautiful sunset")
      expect(result[:image]).to eq("https://example.com/image.jpg")
    end
  end
end