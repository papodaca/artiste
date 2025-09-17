require "spec_helper"

RSpec.describe PhotoGalleryApp do
  include Rack::Test::Methods

  def app
    PhotoGalleryApp
  end

  let(:photos_path) { File.join(__dir__, "..", "..", "db", "photos") }

  before do
    # Create a real instance for testing instance methods
    @app_instance = PhotoGalleryApp.new(photos_path)

    # Stub the photos_path method to return our test path
    allow_any_instance_of(PhotoGalleryApp).to receive(:photos_path).and_return(photos_path)

    # Enable Sinatra's show_exceptions setting to see detailed error messages
    PhotoGalleryApp.set :show_exceptions, true
  end

  describe "GET /" do
    before do
      # Mock the send_file method to return a successful response with expected content
      allow_any_instance_of(PhotoGalleryApp).to receive(:send_file) do |instance, file_path|
        if file_path.include?("index.html")
          # Create a mock response that mimics what send_file would do
          instance.headers "Content-Type" => "text/html"
          "<!doctype html><html><head><title>Vite + Svelte</title></head><body><div id='app'></div></body></html>"
        else
          # For other files, return a 404
          instance.status 404
          "File not found"
        end
      end
    end

    it "responds with success" do
      get "/", {}, "HTTP_HOST" => "localhost"
      expect(last_response).to be_successful
    end

    it "serves the Svelte frontend" do
      get "/", {}, "HTTP_HOST" => "localhost"
      expect(last_response.body).to include("Vite + Svelte")
    end
  end

  describe "GET /api/photo-details/*" do
    let(:task) do
      double("GenerationTask",
        output_filename: "ComfyUI_00157_.png",
        prompt: "A beautiful landscape",
        status: "completed",
        username: "testuser",
        user_id: "123",
        workflow_type: "flux",
        queued_at: Time.new(2025, 9, 1, 12, 0, 0),
        started_at: Time.new(2025, 9, 1, 12, 5, 0),
        completed_at: Time.new(2025, 9, 1, 12, 10, 0),
        processing_time_seconds: 300.0,
        parameters: '{"width": 1024, "height": 1024}',
        exif_data: '{"Software": "ComfyUI"}',
        error_message: nil,
        comfyui_prompt_id: "abc123")
    end

    before do
      allow(GenerationTask).to receive(:where).with(output_filename: "ComfyUI_00157_.png").and_return(double(first: task))
    end

    it "returns photo details as JSON" do
      get "/api/photo-details/2025/09/01/ComfyUI_00157_.png", {}, "HTTP_HOST" => "localhost"
      expect(last_response).to be_successful
      expect(last_response.headers["Content-Type"]).to include("application/json")

      json_response = JSON.parse(last_response.body)
      expect(json_response["photo_path"]).to eq("2025/09/01/ComfyUI_00157_.png")
      expect(json_response["task"]["output_filename"]).to eq("ComfyUI_00157_.png")
    end

    it "returns 404 when task is not found" do
      allow(GenerationTask).to receive(:where).with(output_filename: "ComfyUI_00157_.png").and_return(double(first: nil))
      get "/api/photo-details/2025/09/01/ComfyUI_00157_.png", {}, "HTTP_HOST" => "localhost"
      expect(last_response.status).to eq(404)
    end
  end

  describe "#get_photos" do
    let(:task1) do
      task = double("GenerationTask")
      allow(task).to receive(:completed_at).and_return(Time.new(2025, 9, 1, 12, 0, 0))
      allow(task).to receive(:output_filename).and_return("ComfyUI_00157_.png")
      allow(task).to receive(:file_path).and_return("db/photos/2025/09/01")
      task
    end

    let(:task2) do
      task = double("GenerationTask")
      allow(task).to receive(:completed_at).and_return(Time.new(2025, 9, 1, 13, 0, 0))
      allow(task).to receive(:output_filename).and_return("ComfyUI_00158_.jpg")
      allow(task).to receive(:file_path).and_return("db/photos/2025/09/01")
      task
    end

    before do
      # Mock the GenerationTask.pub scope to return our test tasks
      # Create a mock dataset that responds to reverse_order
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:reverse_order).with(:completed_at).and_return([task2, task1])
      allow(GenerationTask).to receive(:pub).and_return(mock_dataset)
    end

    it "returns sorted list of photo paths from completed tasks" do
      # Test the get_photos method by calling it directly on the class with a new instance
      app_instance = PhotoGalleryApp.allocate
      app_instance.instance_variable_set(:@photos_path, photos_path)
      photos = app_instance.get_photos
      # Photos should be sorted by completed_at in descending order (newest first)
      expect(photos).to eq(["2025/09/01/ComfyUI_00158_.jpg", "2025/09/01/ComfyUI_00157_.png"])
    end

    it "returns paginated list of photo paths when offset and limit are specified" do
      # Test the get_photos method with pagination
      app_instance = PhotoGalleryApp.allocate
      app_instance.instance_variable_set(:@photos_path, photos_path)
      photos = app_instance.get_photos(offset: 1, limit: 1)
      # With descending order, the second item should be the older photo
      expect(photos).to eq(["2025/09/01/ComfyUI_00157_.png"])
    end

    it "returns empty array when no completed tasks exist" do
      # Test the get_photos method by calling it directly on the class with a new instance
      app_instance = PhotoGalleryApp.allocate
      app_instance.instance_variable_set(:@photos_path, photos_path)
      # Create a mock dataset that responds to reverse_order and returns an empty array
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:reverse_order).with(:completed_at).and_return([])
      allow(GenerationTask).to receive(:pub).and_return(mock_dataset)
      expect(app_instance.get_photos).to eq([])
    end

    it "handles tasks with nil output_filename" do
      # Create a task with nil output_filename
      task_with_nil = double("GenerationTask")
      allow(task_with_nil).to receive(:completed_at).and_return(Time.new(2025, 9, 1, 14, 0, 0))
      allow(task_with_nil).to receive(:output_filename).and_return(nil)
      allow(task_with_nil).to receive(:file_path).and_return("db/photos/2025/09/01")

      # Mock GenerationTask.pub to return tasks including one with nil output_filename
      # Create a mock dataset that responds to reverse_order
      mock_dataset = double("Dataset")
      allow(mock_dataset).to receive(:reverse_order).with(:completed_at).and_return([task2, task_with_nil, task1])
      allow(GenerationTask).to receive(:pub).and_return(mock_dataset)

      # Test the get_photos method
      app_instance = PhotoGalleryApp.allocate
      app_instance.instance_variable_set(:@photos_path, photos_path)
      photos = app_instance.get_photos
      # Photos should be sorted by completed_at in descending order (newest first)
      # The task_with_nil should be filtered out
      expect(photos).to eq(["2025/09/01/ComfyUI_00158_.jpg", "2025/09/01/ComfyUI_00157_.png"])
    end
  end
end
