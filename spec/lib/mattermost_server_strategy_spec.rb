require "spec_helper"

RSpec.describe MattermostServerStrategy do
  let(:options) do
    {
      mattermost_url: "https://mattermost.example.com",
      mattermost_token: "test-token",
      mattermost_channels: ["channel1", "channel2"]
    }
  end

  describe "#initialize" do
    before do
      # Stub HTTParty methods on the class
      allow(MattermostClient).to receive(:get).and_return({
        "id" => "bot-id",
        "username" => "bot-name"
      })
      allow(MattermostClient).to receive(:base_uri)
      allow(MattermostClient).to receive(:headers)
    end

    it "initializes with provided options" do
      strategy = described_class.new(**options)

      expect(strategy.instance_variable_get(:@mattermost_url)).to eq("https://mattermost.example.com")
      expect(strategy.instance_variable_get(:@mattermost_token)).to eq("test-token")
      expect(strategy.instance_variable_get(:@mattermost_channels)).to eq(["channel1", "channel2"])
    end

    it "sets up websocket URI correctly for HTTPS" do
      strategy = described_class.new(**options)
      websocket_uri = strategy.instance_variable_get(:@websocket_uri)

      expect(websocket_uri.scheme).to eq("wss")
      expect(websocket_uri.host).to eq("mattermost.example.com")
      expect(websocket_uri.path).to eq("/api/v4/websocket")
    end

    it "sets up websocket URI correctly for HTTP" do
      http_options = options.merge(mattermost_url: "http://mattermost.example.com")
      strategy = described_class.new(**http_options)
      websocket_uri = strategy.instance_variable_get(:@websocket_uri)

      expect(websocket_uri.scheme).to eq("ws")
      expect(websocket_uri.host).to eq("mattermost.example.com")
    end

    it "sets up API URI correctly" do
      strategy = described_class.new(**options)
      api_uri = strategy.instance_variable_get(:@api_uri)

      expect(api_uri.scheme).to eq("https")
      expect(api_uri.host).to eq("mattermost.example.com")
      expect(api_uri.path).to eq("/api/v4")
    end

    it "sets up MattermostClient" do
      described_class.new(**options)

      expect(MattermostClient).to have_received(:base_uri).with("https://mattermost.example.com/api/v4")
      expect(MattermostClient).to have_received(:headers).with({
        "Authorization" => "Bearer test-token",
        "Accept" => "application/json"
      })
    end

    it "stores bot ID and name" do
      allow(MattermostClient).to receive(:get).and_return({
        "id" => "test-bot-id",
        "username" => "test-bot-name"
      })

      strategy = described_class.new(**options)

      expect(strategy.instance_variable_get(:@mattermost_bot_id)).to eq("test-bot-id")
      expect(strategy.instance_variable_get(:@mattermost_bot_name)).to eq("test-bot-name")
    end
  end

  describe "#respond" do
    let(:strategy) { described_class.allocate }
    let(:message) do
      {
        "data" => {
          "post" => {
            "channel_id" => "channel-id",
            "id" => "post-id"
          },
          "channel_type" => "O"
        }
      }
    end
    let(:reply) { "Test reply" }

    before do
      # Stub HTTParty methods
      allow(MattermostClient).to receive(:post)
      strategy.instance_variable_set(:@client, MattermostClient)
    end

    it "sends a post to the channel with root_id for non-direct messages" do
      strategy.respond(message, reply)

      expect(MattermostClient).to have_received(:post).with(
        "/posts",
        headers: {"Content-Type" => "application/json"},
        body: {
          channel_id: "channel-id",
          message: "Test reply",
          root_id: "post-id"
        }.to_json
      )
    end

    it "sends a post to the channel without root_id for direct messages" do
      message["data"]["channel_type"] = "D"
      strategy.respond(message, reply)

      expect(MattermostClient).to have_received(:post).with(
        "/posts",
        headers: {"Content-Type" => "application/json"},
        body: {
          channel_id: "channel-id",
          message: "Test reply"
        }.to_json
      )
    end
  end

  describe "#update" do
    let(:strategy) { described_class.allocate }
    let(:message) do
      {
        "data" => {
          "post" => {
            "channel_id" => "channel-id"
          }
        }
      }
    end
    let(:reply) { {"id" => "reply-id"} }
    let(:update) { "Updated message" }

    before do
      # Stub HTTParty methods
      allow(MattermostClient).to receive(:put)
      strategy.instance_variable_set(:@client, MattermostClient)
    end

    it "updates an existing post" do
      strategy.update(message, reply, update)

      expect(MattermostClient).to have_received(:put).with(
        "/posts/reply-id/patch",
        headers: {"Content-Type" => "application/json"},
        body: {
          post_id: "reply-id",
          message: "Updated message"
        }.to_json
      )
    end
  end

  describe "#upload_file" do
    let(:strategy) { described_class.allocate }
    let(:channel_id) { "channel-id" }
    let(:file) { "file-data" }
    let(:filename) { "test.png" }

    before do
      # Stub HTTParty methods
      allow(MattermostClient).to receive(:post).and_return({
        "file_infos" => [
          {"id" => "file-id-1"},
          {"id" => "file-id-2"}
        ]
      })
      strategy.instance_variable_set(:@client, MattermostClient)
    end

    it "uploads file with correct parameters" do
      file_ids = strategy.send(:upload_file, channel_id, file, filename)

      expect(MattermostClient).to have_received(:post).with(
        "/files",
        query: {
          channel_id: "channel-id",
          filename: "test.png"
        },
        multipart: true,
        body: {
          channel_id: "channel-id",
          files: "file-data"
        }
      )
      expect(file_ids).to eq(["file-id-1", "file-id-2"])
    end

    it "uses default filename when not provided" do
      allow(MattermostClient).to receive(:post).and_return({
        "file_infos" => [
          {"id" => "file-id-1"}
        ]
      })

      strategy.send(:upload_file, channel_id, file, nil)

      expect(MattermostClient).to have_received(:post) do |path, options|
        expect(options[:query][:filename]).to eq("generated.png")
      end
    end
  end

  describe "#get_self_user" do
    let(:strategy) { described_class.allocate }

    before do
      # Stub HTTParty methods
      allow(MattermostClient).to receive(:get).and_return({
        "id" => "fetched-bot-id",
        "username" => "fetched-bot-name"
      })
      strategy.instance_variable_set(:@client, MattermostClient)
    end

    it "fetches and stores user information" do
      strategy.send(:get_self_user)

      expect(MattermostClient).to have_received(:get).with("/users/me")
      expect(strategy.instance_variable_get(:@mattermost_bot_id)).to eq("fetched-bot-id")
      expect(strategy.instance_variable_get(:@mattermost_bot_name)).to eq("fetched-bot-name")
    end
  end

  describe "#download_attached_images" do
    let(:strategy) { described_class.allocate }
    let(:msg_data) do
      {
        "data" => {
          "post" => {
            "id" => "post-id",
            "channel_id" => "channel-id",
            "metadata" => {
              "files" => []
            }
          },
          "user_id" => "user-id",
          "sender_name" => "test-user"
        }
      }
    end

    before do
      # Stub private methods
      allow(strategy).to receive(:download_file)
      allow(strategy).to receive(:save_downloaded_file)
    end

    context "when post has no files" do
      it "does not download any files" do
        strategy.send(:download_attached_images, msg_data)
        expect(strategy).not_to have_received(:download_file)
        expect(strategy).not_to have_received(:save_downloaded_file)
        expect(msg_data["attached_files"]).to be_nil
      end
    end

    context "when post has files" do
      let(:msg_data_with_files) do
        msg_data.deep_dup.tap do |data|
          data["data"]["post"]["metadata"]["files"] = [
            {"id" => "file-id-1", "name" => "image1.png", "mime_type" => "image/png"},
            {"id" => "file-id-2", "name" => "image2.jpg", "mime_type" => "image/jpeg"}
          ]
        end
      end

      before do
        allow(strategy).to receive(:download_file).with("file-id-1").and_return("file-data-1")
        allow(strategy).to receive(:download_file).with("file-id-2").and_return("file-data-2")
        allow(strategy).to receive(:save_downloaded_file).with("file-data-1", "image1.png").and_return("dp/tmp/image1_1234567890.png")
        allow(strategy).to receive(:save_downloaded_file).with("file-data-2", "image2.jpg").and_return("dp/tmp/image2_1234567890.jpg")
      end

      it "downloads each file and adds paths to msg_data" do
        strategy.send(:download_attached_images, msg_data_with_files)
        expect(strategy).to have_received(:download_file).with("file-id-1")
        expect(strategy).to have_received(:download_file).with("file-id-2")
        expect(strategy).to have_received(:save_downloaded_file).with("file-data-1", "image1.png")
        expect(strategy).to have_received(:save_downloaded_file).with("file-data-2", "image2.jpg")
        expect(msg_data_with_files["attached_files"]).to eq(["file://dp/tmp/image1_1234567890.png", "file://dp/tmp/image2_1234567890.jpg"])
      end

      it "handles download errors gracefully" do
        allow(strategy).to receive(:download_file).with("file-id-1").and_raise("Download error")
        expect { strategy.send(:download_attached_images, msg_data_with_files) }.not_to raise_error
        expect(strategy).to have_received(:save_downloaded_file).with("file-data-2", "image2.jpg")
        expect(msg_data_with_files["attached_files"]).to eq(["file://dp/tmp/image2_1234567890.jpg"])
      end
    end
  end

  describe "#download_file" do
    let(:strategy) { described_class.allocate }
    let(:file_id) { "file-id" }
    let(:file_data) { "binary-file-data" }

    before do
      # Stub HTTParty methods
      mock_response = double("response", body: file_data)
      allow(MattermostClient).to receive(:get).and_return(mock_response)
      strategy.instance_variable_set(:@client, MattermostClient)
    end

    it "downloads file data" do
      downloaded_data = strategy.send(:download_file, file_id)
      expect(MattermostClient).to have_received(:get).with(
        "/files/#{file_id}",
        headers: {"Accept" => "application/octet-stream"}
      )
      expect(downloaded_data).to eq(file_data)
    end
  end

  describe "#save_downloaded_file" do
    let(:strategy) { described_class.allocate }
    let(:file_data) { "binary-file-data" }
    let(:filename) { "test.png" }
    let(:timestamp) { 1758981480 }

    before do
      # Stub file system operations
      allow(Dir).to receive(:exist?).with("db/tmp").and_return(false)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:binwrite)
      # Mock Time.now.to_i directly
      allow(Time).to receive(:now).and_return(double("time", to_i: timestamp))
    end

    it "creates tmp directory" do
      strategy.send(:save_downloaded_file, file_data, filename)
      expect(FileUtils).to have_received(:mkdir_p).with("db/tmp")
    end

    it "writes file to tmp directory" do
      expected_path = "db/tmp/test_1758981480.png"
      strategy.send(:save_downloaded_file, file_data, filename)
      expect(File).to have_received(:binwrite).with(expected_path, file_data)
    end

    it "returns the file path" do
      expected_path = "db/tmp/test_1758981480.png"
      result = strategy.send(:save_downloaded_file, file_data, filename)
      expect(result).to eq(expected_path)
    end
  end
end
