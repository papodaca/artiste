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
end
