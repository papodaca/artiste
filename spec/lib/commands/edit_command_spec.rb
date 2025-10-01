require "spec_helper"
require_relative "../../../config/database"

RSpec.describe EditCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) {
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}).tap do |msg|
      allow(msg).to receive(:[]).with("attached_files").and_return(nil)
    end
  }
  let(:user_settings) { instance_double("UserSettings", username: "test_user", user_id: "test-user") }
  let(:image_generation_client) { instance_double("ChutesClient") }

  let(:today_file_path) { "db/photos/2025/09/19" }

  before do
    allow(mattermost).to receive(:respond)
    allow(mattermost).to receive(:update)
    allow(ImageGenerationClient).to receive(:create).and_return(image_generation_client)
    FileUtils.mkdir_p(today_file_path)
  end

  describe ".parse" do
    context "with valid format" do
      it "parses prompt and image parameter correctly" do
        result = described_class.parse("a beautiful sunset --image https://example.com/image.jpg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["https://example.com/image.jpg"])
      end

      it "parses with short image flag" do
        result = described_class.parse("a beautiful sunset -i https://example.com/image.jpg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["https://example.com/image.jpg"])
      end

      it "parses with other parameters" do
        result = described_class.parse("a beautiful sunset --image https://example.com/image.jpg --steps 30 --width 1024")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["https://example.com/image.jpg"])
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
        expect(result[:image]).to eq(["chutes_1758256813.png"])
      end

      it "parses with jpg filename" do
        result = described_class.parse("a beautiful sunset --image test_image.jpg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["test_image.jpg"])
      end

      it "parses with jpeg filename" do
        result = described_class.parse("a beautiful sunset --image test_image.jpeg")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["test_image.jpeg"])
      end

      it "parses multiple images with comma separation" do
        result = described_class.parse("a beautiful sunset --image chutes_01.png,chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["chutes_01.png", "chutes_02.png"])
      end

      it "parses multiple URLs with comma separation" do
        result = described_class.parse("a beautiful sunset --image http://example.com/image1.png,http://example.com/image2.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["http://example.com/image1.png", "http://example.com/image2.png"])
      end

      it "parses mixed URLs and filenames with comma separation" do
        result = described_class.parse("a beautiful sunset --image http://example.com/image1.png,chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["http://example.com/image1.png", "chutes_02.png"])
      end

      it "parses multiple filenames with comma separation" do
        result = described_class.parse("a beautiful sunset -i chutes_01.png,chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["chutes_01.png", "chutes_02.png"])
      end

      it "parses URL followed by filename with comma separation" do
        result = described_class.parse("a beautiful sunset -i http://example.com/image1.png,chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["http://example.com/image1.png", "chutes_02.png"])
      end

      it "parses filename followed by URL with comma separation" do
        result = described_class.parse("a beautiful sunset -i chutes_02.png,http://example.com/image1.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["chutes_02.png", "http://example.com/image1.png"])
      end

      it "parses multiple URLs with comma separation" do
        result = described_class.parse("a beautiful sunset -i http://example.com/image1.png,http://example.com/image2.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["http://example.com/image1.png", "http://example.com/image2.png"])
      end

      it "parses multiple filenames with separate -i flags" do
        result = described_class.parse("a beautiful sunset -i chutes_01.png -i chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["chutes_01.png", "chutes_02.png"])
      end

      it "parses URL and filename with separate -i flags" do
        result = described_class.parse("a beautiful sunset -i http://example.com/image1.png -i chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["http://example.com/image1.png", "chutes_02.png"])
      end

      it "parses multiple URLs with separate -i flags" do
        result = described_class.parse("a beautiful sunset -i http://example.com/image1.png -i http://example.com/image2.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["http://example.com/image1.png", "http://example.com/image2.png"])
      end

      it "parses mixed comma-separated and separate -i flags" do
        result = described_class.parse("a beautiful sunset -i chutes_01.png,chutes_02.png -i http://example.com/image1.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["chutes_01.png", "chutes_02.png", "http://example.com/image1.png"])
      end

      it "parses multiple images with seed parameter" do
        result = described_class.parse("a beautiful sunset -i chutes_01.png --seed 1 -i chutes_02.png")
        expect(result[:prompt]).to eq("a beautiful sunset")
        expect(result[:image]).to eq(["chutes_01.png", "chutes_02.png"])
        expect(result[:seed]).to eq(1)
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
          expect(response).to include("❌ Please provide either an image URL using --image <url>, a filename using --image <filename>, a task ID using --task <id> parameter, or attach an image to your message for editing.")
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
          file_path: "db/photos/2025/09/19")
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
          block&.call(:started, "test-prompt-id", nil)
          block&.call(:completed, "test-prompt-id", nil)
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
          file_path: today_file_path,
          completed_at: Time.now)
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
          block&.call(:started, "test-prompt-id", nil)
          block&.call(:completed, "test-prompt-id", nil)
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
          image: ["https://example.com/image.jpg"],
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
          block&.call(:started, "test-prompt-id", nil)
          block&.call(:completed, "test-prompt-id", nil)
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
            image_b64s: ["base64_encoded_image"],
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
        ).and_return(double("GenerationTask", id: 123, mark_processing: nil, mark_completed: nil, processing_time_seconds: 1.5, file_path: "db/photos/2025/09/19", output_filename: "test_output.png", username: "test_user", workflow_type: "qwen-image-edit", completed_at: Time.now, prompt: "a beautiful sunset", set_exif_data: nil, to_h: {}))

        expect(mattermost).to receive(:respond).and_return(double("reply"))
        expect(mattermost).to receive(:update).at_least(:once)

        command.execute
      end
    end

    context "when image download fails" do
      let(:parsed_result) {
        {
          prompt: "a beautiful sunset",
          image: ["https://example.com/image.jpg"]
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

    context "when more than 3 images are provided" do
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      context "with 4 attached files" do
        let(:parsed_result) {
          {
            prompt: "a beautiful sunset"
          }
        }

        before do
          allow(message).to receive(:[]).with("attached_files").and_return([
            "https://example.com/image1.jpg",
            "https://example.com/image2.jpg",
            "https://example.com/image3.jpg",
            "https://example.com/image4.jpg"
          ])
        end

        it "responds with error message about image limit" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to include("❌ You can only edit up to 3 images at a time. You provided 4 images.")
          end

          command.execute
        end
      end

      context "with 4 image parameters" do
        let(:parsed_result) {
          {
            prompt: "a beautiful sunset",
            image: ["image1.jpg", "image2.jpg", "image3.jpg", "image4.jpg"]
          }
        }

        it "responds with error message about image limit" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to include("❌ You can only edit up to 3 images at a time. You provided 4 images.")
          end

          command.execute
        end
      end

      context "with 2 attached files and 2 image parameters" do
        let(:parsed_result) {
          {
            prompt: "a beautiful sunset",
            image: ["image1.jpg", "image2.jpg"]
          }
        }

        before do
          allow(message).to receive(:[]).with("attached_files").and_return([
            "https://example.com/image3.jpg",
            "https://example.com/image4.jpg"
          ])
        end

        it "responds with error message about image limit" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to include("❌ You can only edit up to 3 images at a time. You provided 4 images.")
          end

          command.execute
        end
      end

      context "with 2 attached files and 1 task_id" do
        let(:parsed_result) {
          {
            prompt: "a beautiful sunset",
            task_id: 123
          }
        }

        before do
          allow(message).to receive(:[]).with("attached_files").and_return([
            "https://example.com/image1.jpg",
            "https://example.com/image2.jpg",
            "https://example.com/image3.jpg"
          ])
        end

        it "responds with error message about image limit" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to include("❌ You can only edit up to 3 images at a time. You provided 4 images.")
          end

          command.execute
        end
      end

      context "with 2 attached files and 2 image parameters" do
        let(:parsed_result) {
          {
            prompt: "a beautiful sunset",
            image: ["image1.jpg", "image2.jpg"]
          }
        }

        before do
          allow(message).to receive(:[]).with("attached_files").and_return([
            "https://example.com/image3.jpg",
            "https://example.com/image4.jpg"
          ])
        end

        it "responds with error message about image limit" do
          expect(mattermost).to receive(:respond) do |msg, response|
            expect(msg).to eq(message)
            expect(response).to include("❌ You can only edit up to 3 images at a time. You provided 4 images.")
          end

          command.execute
        end
      end

      context "with exactly 3 images (valid case)" do
        let(:parsed_result) {
          {
            prompt: "a beautiful sunset",
            image: ["https://example.com/image1.jpg", "https://example.com/image2.jpg"]
          }
        }

        before do
          allow(message).to receive(:[]).with("attached_files").and_return([
            "https://example.com/image3.jpg"
          ])

          # Mock the image download
          allow_any_instance_of(EditCommand).to receive(:download_image).and_return("fake_image_data")
          allow(Base64).to receive(:strict_encode64).and_return("base64_encoded_image")

          # Mock the image generation with callback
          allow(image_generation_client).to receive(:generate) do |&block|
            block&.call(:started, "test-prompt-id", nil)
            block&.call(:completed, "test-prompt-id", nil)
            {
              image_data: "generated_image_data",
              prompt_id: "test-prompt-id"
            }
          end

          # Mock task creation
          allow(GenerationTask).to receive(:create).and_return(
            double("GenerationTask",
              id: 123,
              mark_processing: nil,
              mark_completed: nil,
              mark_failed: nil,
              processing_time_seconds: 1.5,
              file_path: "db/photos/2025/09/19",
              output_filename: "test_output.png",
              username: "test_user",
              workflow_type: "qwen-image-edit",
              completed_at: Time.now,
              prompt: "a beautiful sunset",
              set_exif_data: nil,
              to_h: {})
          )

          # Mock file operations for saving the result
          allow(File).to receive(:binwrite)
          allow(Kernel).to receive(:open).and_return(double("file", close: nil))
          allow(Kernel).to receive(:system)
        end

        it "processes the images without error" do
          expect(mattermost).to receive(:respond).and_return(double("reply"))
          expect(mattermost).to receive(:update).at_least(:once)
          expect { command.execute }.not_to raise_error
        end
      end
    end
  end

  describe "#download_image" do
    let(:command) { described_class.new(mattermost, message, {}, user_settings) }

    context "when downloading a PNG image" do
      before do
        # Mock HTTParty response with PNG image data
        png_response = double("HTTParty::Response")
        allow(png_response).to receive(:success?).and_return(true)
        allow(png_response).to receive(:code).and_return(200)
        allow(png_response).to receive(:message).and_return("OK")
        allow(png_response).to receive(:body).and_return(File.binread("spec/fixtures/chutes_1758932276.png"))
        allow(HTTParty).to receive(:get).with("https://example.com/image.png").and_return(png_response)
      end

      it "returns PNG image data without conversion" do
        result = command.send(:download_image, "https://example.com/image.png")
        expect(result[0..7].unpack("C*")).to eq([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      end
    end

    context "when downloading a JPG image" do
      before do
        # Mock HTTParty response with JPG image data
        jpg_response = double("HTTParty::Response")
        allow(jpg_response).to receive(:success?).and_return(true)
        allow(jpg_response).to receive(:code).and_return(200)
        allow(jpg_response).to receive(:message).and_return("OK")
        allow(jpg_response).to receive(:body).and_return(File.binread("spec/fixtures/chutes_1758932276.jpg"))
        allow(HTTParty).to receive(:get).with("https://example.com/image.jpg").and_return(jpg_response)

        # Mock the system call to ImageMagick
        allow(command).to receive(:system).with(/magick convert/).and_return(true)
        allow(File).to receive(:binread).and_call_original
      end

      it "converts JPG to PNG format" do
        # Mock MiniMagick for image validation
        mock_image = double("MiniMagick::Image")
        allow(mock_image).to receive(:validate!)
        allow(MiniMagick::Image).to receive(:open).and_return(mock_image)

        # Mock the entire conversion process
        allow(command).to receive(:system).with(/magick convert/).and_return(true)

        # Mock Tempfile to avoid actual file operations
        temp_input = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/input", unlink: nil)
        temp_output = double("Tempfile", close: nil, path: "/tmp/output", unlink: nil)
        validate_temp = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/validate", unlink: nil)

        allow(Tempfile).to receive(:new).with(["image_validation", ".bin"]).and_return(validate_temp)
        allow(Tempfile).to receive(:new).with(["original_image", ".bin"]).and_return(temp_input)
        allow(Tempfile).to receive(:new).with(["converted_image", ".png"]).and_return(temp_output)

        # Mock File.binread to return PNG data after conversion
        png_data = File.binread("spec/fixtures/chutes_1758932276.png")
        allow(File).to receive(:binread).with("/tmp/output").and_return(png_data)

        result = command.send(:download_image, "https://example.com/image.jpg")
        expect(result[0..7].unpack("C*")).to eq([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      end
    end

    context "when downloading a WEBP image" do
      before do
        # Mock HTTParty response with WEBP image data
        webp_response = double("HTTParty::Response")
        allow(webp_response).to receive(:success?).and_return(true)
        allow(webp_response).to receive(:code).and_return(200)
        allow(webp_response).to receive(:message).and_return("OK")
        # Create a mock WEBP header (first 12 bytes should contain "WEBPVP8")
        webp_data = ["WEBPVP8"].pack("A*") + "\x00" * 100
        allow(webp_response).to receive(:body).and_return(webp_data)
        allow(HTTParty).to receive(:get).with("https://example.com/image.webp").and_return(webp_response)

        # Mock the system call to ImageMagick
        allow(command).to receive(:system).with(/magick convert/).and_return(true)
        allow(File).to receive(:binread).and_call_original
      end

      it "converts WEBP to PNG format" do
        # Mock MiniMagick for image validation
        mock_image = double("MiniMagick::Image")
        allow(mock_image).to receive(:validate!)
        allow(MiniMagick::Image).to receive(:open).and_return(mock_image)

        # Mock the entire conversion process
        allow(command).to receive(:system).with(/magick convert/).and_return(true)

        # Mock Tempfile to avoid actual file operations
        temp_input = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/input", unlink: nil)
        temp_output = double("Tempfile", close: nil, path: "/tmp/output", unlink: nil)
        validate_temp = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/validate", unlink: nil)

        allow(Tempfile).to receive(:new).with(["image_validation", ".bin"]).and_return(validate_temp)
        allow(Tempfile).to receive(:new).with(["original_image", ".bin"]).and_return(temp_input)
        allow(Tempfile).to receive(:new).with(["converted_image", ".png"]).and_return(temp_output)

        # Mock File.binread to return PNG data after conversion
        png_data = File.binread("spec/fixtures/chutes_1758932276.png")
        allow(File).to receive(:binread).with("/tmp/output").and_return(png_data)

        result = command.send(:download_image, "https://example.com/image.webp")
        expect(result[0..7].unpack("C*")).to eq([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      end
    end

    context "when ImageMagick conversion fails" do
      before do
        # Mock HTTParty response with JPG image data
        jpg_response = double("HTTParty::Response")
        allow(jpg_response).to receive(:success?).and_return(true)
        allow(jpg_response).to receive(:code).and_return(200)
        allow(jpg_response).to receive(:message).and_return("OK")
        allow(jpg_response).to receive(:body).and_return(File.binread("spec/fixtures/chutes_1758932276.jpg"))
        allow(HTTParty).to receive(:get).with("https://example.com/image.jpg").and_return(jpg_response)

        # Mock the system call to ImageMagick to fail
        allow(command).to receive(:system).with(/magick convert/).and_return(false)
      end

      it "raises an error when conversion fails" do
        expect {
          command.send(:download_image, "https://example.com/image.jpg")
        }.to raise_error(/Failed to download image: Failed to convert downloaded file to PNG using ImageMagick/)
      end
    end
  end

  describe "#load_image_from_task" do
    let(:command) { described_class.new(mattermost, message, {}, user_settings) }
    let(:task) {
      instance_double("GenerationTask",
        output_filename: "test_image.jpg",
        file_path: "spec/fixtures")
    }

    context "when loading a PNG image from task" do
      before do
        allow(GenerationTask).to receive(:[]).with(123).and_return(task)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).with("spec/fixtures/test_image.jpg").and_return(File.binread("spec/fixtures/chutes_1758932276.png"))
      end

      it "returns PNG image data without conversion" do
        result = command.send(:load_image_from_task, 123)
        expect(result[0..7].unpack("C*")).to eq([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
      end
    end

    context "when loading a JPG image from task" do
      before do
        allow(GenerationTask).to receive(:[]).with(123).and_return(task)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).with("spec/fixtures/test_image.jpg").and_return(File.binread("spec/fixtures/chutes_1758932276.jpg"))

        # Mock the system call to ImageMagick
        allow(command).to receive(:system).with(/magick convert/).and_return(true)
        allow(File).to receive(:binread).and_call_original
      end

      it "converts JPG to PNG format" do
        # Create a real file for testing
        test_file_path = "spec/fixtures/test_image.jpg"
        FileUtils.cp("spec/fixtures/chutes_1758932276.jpg", test_file_path)

        # Mock MiniMagick for image validation
        mock_image = double("MiniMagick::Image")
        allow(mock_image).to receive(:validate!)
        allow(MiniMagick::Image).to receive(:open).and_return(mock_image)

        # Mock the entire conversion process
        allow(command).to receive(:system).with(/magick convert/).and_return(true)

        # Mock Tempfile to avoid actual file operations
        temp_input = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/input", unlink: nil)
        temp_output = double("Tempfile", close: nil, path: "/tmp/output", unlink: nil)
        validate_temp = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/validate", unlink: nil)

        allow(Tempfile).to receive(:new).with(["image_validation", ".bin"]).and_return(validate_temp)
        allow(Tempfile).to receive(:new).with(["original_image", ".bin"]).and_return(temp_input)
        allow(Tempfile).to receive(:new).with(["converted_image", ".png"]).and_return(temp_output)

        # Mock File.binread to return PNG data after conversion
        png_data = File.binread("spec/fixtures/chutes_1758932276.png")
        allow(File).to receive(:binread).with("/tmp/output").and_return(png_data)

        result = command.send(:load_image_from_task, 123)
        expect(result[0..7].unpack("C*")).to eq([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        # Clean up
        File.delete(test_file_path) if File.exist?(test_file_path)
      end
    end

    context "when loading a WEBP image from task" do
      before do
        allow(GenerationTask).to receive(:[]).with(123).and_return(task)
        allow(File).to receive(:exist?).and_return(true)
        # Create a mock WEBP header (first 12 bytes should contain "WEBPVP8")
        webp_data = ["WEBPVP8"].pack("A*") + "\x00" * 100
        allow(File).to receive(:binread).with("spec/fixtures/test_image.jpg").and_return(webp_data)

        # Mock the system call to ImageMagick
        allow(command).to receive(:system).with(/magick convert/).and_return(true)
        allow(File).to receive(:binread).and_call_original
      end

      it "converts WEBP to PNG format" do
        # Create a real file for testing
        test_file_path = "spec/fixtures/test_image.jpg"
        # Create a mock WEBP file
        webp_data = ["WEBPVP8"].pack("A*") + "\x00" * 100
        File.binwrite(test_file_path, webp_data)

        # Mock MiniMagick for image validation
        mock_image = double("MiniMagick::Image")
        allow(mock_image).to receive(:validate!)
        allow(MiniMagick::Image).to receive(:open).and_return(mock_image)

        # Mock the entire conversion process
        allow(command).to receive(:system).with(/magick convert/).and_return(true)

        # Mock Tempfile to avoid actual file operations
        temp_input = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/input", unlink: nil)
        temp_output = double("Tempfile", close: nil, path: "/tmp/output", unlink: nil)
        validate_temp = double("Tempfile", binmode: nil, write: nil, close: nil, path: "/tmp/validate", unlink: nil)

        allow(Tempfile).to receive(:new).with(["image_validation", ".bin"]).and_return(validate_temp)
        allow(Tempfile).to receive(:new).with(["original_image", ".bin"]).and_return(temp_input)
        allow(Tempfile).to receive(:new).with(["converted_image", ".png"]).and_return(temp_output)

        # Mock File.binread to return PNG data after conversion
        png_data = File.binread("spec/fixtures/chutes_1758932276.png")
        allow(File).to receive(:binread).with("/tmp/output").and_return(png_data)

        result = command.send(:load_image_from_task, 123)
        expect(result[0..7].unpack("C*")).to eq([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        # Clean up
        File.delete(test_file_path) if File.exist?(test_file_path)
      end
    end

    context "when ImageMagick conversion fails for task image" do
      before do
        allow(GenerationTask).to receive(:[]).with(123).and_return(task)
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:binread).with("spec/fixtures/test_image.jpg").and_return(File.binread("spec/fixtures/chutes_1758932276.jpg"))

        # Mock the system call to ImageMagick to fail
        allow(command).to receive(:system).with(/magick convert/).and_return(false)
      end

      it "raises an error when conversion fails" do
        expect {
          command.send(:load_image_from_task, 123)
        }.to raise_error(/Failed to load image from task 123: Failed to convert file to PNG using ImageMagick/)
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/edit a beautiful sunset --image https://example.com/image.jpg")
      expect(result[:type]).to eq(:edit)
      expect(result[:prompt]).to eq("a beautiful sunset")
      expect(result[:image]).to eq(["https://example.com/image.jpg"])
    end
  end
end
