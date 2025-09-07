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

    # Disable Sinatra's show_exceptions setting for cleaner test output
    PhotoGalleryApp.set :show_exceptions, false
  end

  describe "GET /" do
    before do
      # Mock get_photos for route testing
      allow_any_instance_of(PhotoGalleryApp).to receive(:get_photos).and_return([
        "2025/09/01/ComfyUI_00157_.png",
        "2025/09/01/ComfyUI_00158_.jpg"
      ])
    end

    it "responds with success" do
      get "/", {}, "HTTP_HOST" => "localhost"
      expect(last_response).to be_successful
    end

    it "renders the index template" do
      allow_any_instance_of(PhotoGalleryApp).to receive(:erb).with(:index).and_return("<html><body>Photo Gallery</body></html>")
      get "/", {}, "HTTP_HOST" => "localhost"
      expect(last_response.body).to include("Photo Gallery")
    end
  end

  describe "GET /photo/*" do
    let(:photo_file) { File.join(photos_path, "2025", "09", "01", "ComfyUI_00157_.png") }
    let(:photo_content) { "fake image content" }

    before do
      # Stub File methods for photo serving
      allow(File).to receive(:realpath).with(photos_path).and_return(photos_path)
      allow(File).to receive(:realpath).with(photo_file).and_return(photo_file)
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(photo_file).and_return(true)
      allow(File).to receive(:read).with(photo_file).and_return(photo_content)

      # Stub File.exist? for the public directory check that Sinatra does
      allow(File).to receive(:exist?).with(File.join(File.dirname(__FILE__), "../../lib/public")).and_return(false)

      # Handle nonexistent file
      nonexistent_file = File.join(photos_path, "nonexistent.png")
      allow(File).to receive(:exist?).with(nonexistent_file).and_return(false)
      allow(File).to receive(:realpath).with(nonexistent_file).and_raise(Errno::ENOENT, "No such file or directory")
    end

    it "serves a photo file" do
      get "/photo/2025/09/01/ComfyUI_00157_.png", {}, "HTTP_HOST" => "localhost"
      expect(last_response.body).to eq(photo_content)
      expect(last_response.headers["Content-Type"]).to eq("image/png")
    end

    it "returns 404 for non-existent photo" do
      get "/photo/nonexistent.png", {}, "HTTP_HOST" => "localhost"
      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /details/*" do
    let(:task) { double("GenerationTask", output_filename: "ComfyUI_00157_.png", prompt: "A beautiful landscape") }

    before do
      allow(GenerationTask).to receive(:where).and_return([task])
    end

    it "shows details for a photo" do
      allow_any_instance_of(PhotoGalleryApp).to receive(:erb).with(:details).and_return("<html><body>Details</body></html>")
      get "/details/2025/09/01/ComfyUI_00157_.png", {}, "HTTP_HOST" => "localhost"
      expect(last_response).to be_successful
    end

    it "returns 404 when task is not found" do
      allow(GenerationTask).to receive(:where).and_return([])
      get "/details/2025/09/01/ComfyUI_00157_.png", {}, "HTTP_HOST" => "localhost"
      expect(last_response.status).to eq(404)
    end
  end

  describe "#get_photos" do
    let(:photo_files) do
      [
        File.join(photos_path, "2025", "09", "01", "ComfyUI_00157_.png"),
        File.join(photos_path, "2025", "09", "01", "ComfyUI_00158_.jpg")
      ]
    end

    before do
      allow(Dir).to receive(:exist?).with(photos_path).and_return(true)
      allow(Dir).to receive(:glob).with(File.join(photos_path, "**", "*")).and_return(photo_files)

      # Stub File methods for each photo file
      photo_files.each do |file|
        allow(File).to receive(:file?).with(file).and_return(true)
      end

      allow(File).to receive(:extname).with(photo_files[0]).and_return(".png")
      allow(File).to receive(:extname).with(photo_files[1]).and_return(".jpg")
    end

    it "returns sorted list of photo paths" do
      # Test the get_photos method by calling it directly on the class with a new instance
      app_instance = PhotoGalleryApp.allocate
      app_instance.instance_variable_set(:@photos_path, photos_path)
      photos = app_instance.get_photos
      expect(photos).to eq(["2025/09/01/ComfyUI_00157_.png", "2025/09/01/ComfyUI_00158_.jpg"])
    end

    it "returns empty array when photos directory does not exist" do
      # Test the get_photos method by calling it directly on the class with a new instance
      app_instance = PhotoGalleryApp.allocate
      app_instance.instance_variable_set(:@photos_path, photos_path)
      allow(Dir).to receive(:exist?).with(photos_path).and_return(false)
      expect(app_instance.get_photos).to eq([])
    end
  end
end
