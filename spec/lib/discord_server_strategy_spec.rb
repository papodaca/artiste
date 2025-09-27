require "spec_helper"

RSpec.describe DiscordServerStrategy do
  let(:discord_token) { "test-token" }
  let(:discord_channels) { [123456789, 987654321] }
  let(:options) do
    {
      discord_token: discord_token,
      discord_channels: discord_channels
    }
  end

  describe "#initialize" do
    it "initializes with provided options" do
      strategy = described_class.new(**options)

      expect(strategy.instance_variable_get(:@discord_token)).to eq(discord_token)
      expect(strategy.instance_variable_get(:@discord_channels)).to eq(discord_channels)
    end

    it "initializes with empty channels array when not provided" do
      options_without_channels = {discord_token: discord_token}
      strategy = described_class.new(**options_without_channels)

      expect(strategy.instance_variable_get(:@discord_channels)).to eq([])
    end

    it "raises an error when discord_token is nil" do
      expect { described_class.new(discord_token: nil) }.to raise_error("Discord token is required")
    end

    it "raises an error when discord_token is empty" do
      expect { described_class.new(discord_token: "") }.to raise_error("Discord token is required")
    end

    it "creates a Discordrb::Bot instance" do
      # We can't easily mock Discordrb::Bot.new since it's called in initialize
      # Instead, we'll check that the bot instance variable is set
      strategy = described_class.new(**options)
      expect(strategy.instance_variable_get(:@bot)).to be_a(Discordrb::Bot)
    end
  end

  describe "#connect" do
    let(:strategy) { described_class.new(**options) }
    let(:bot_double) { instance_double(Discordrb::Bot) }

    before do
      # Replace the bot instance with our double
      strategy.instance_variable_set(:@bot, bot_double)
      strategy.instance_variable_set(:@message_handler, nil)
    end

    it "stores the message handler block" do
      handler = proc { |message, event| puts "test" }

      # Mock the bot methods that are called during connect
      allow(bot_double).to receive(:ready)
      allow(bot_double).to receive(:mention)
      allow(bot_double).to receive(:message)
      allow(bot_double).to receive(:run)

      strategy.connect(&handler)

      expect(strategy.instance_variable_get(:@message_handler)).to eq(handler)
    end

    it "sets up event handlers" do
      expect(bot_double).to receive(:ready)
      expect(bot_double).to receive(:mention)
      expect(bot_double).to receive(:message)
      expect(bot_double).to receive(:run).with(async: true)

      strategy.connect { |message, event| }
    end
  end

  describe "#respond" do
    let(:strategy) { described_class.new(**options) }
    let(:event_double) { instance_double(Discordrb::Events::MessageEvent) }
    let(:channel_double) { instance_double(Discordrb::Channel) }
    let(:response_double) { instance_double(Discordrb::Message) }
    let(:message) do
      {
        "_event" => event_double
      }
    end
    let(:reply) { "Test response" }

    before do
      allow(event_double).to receive(:channel).and_return(channel_double)
      allow(event_double).to receive(:respond).with(reply).and_return(response_double)
      allow(channel_double).to receive(:id).and_return("12345")
      allow(response_double).to receive(:id).and_return(67890)
    end

    it "sends a message to the channel and returns response data" do
      expect(event_double).to receive(:respond).with(reply)

      result = strategy.respond(message, reply)

      expect(result).to be_a(Hash)
      expect(result["id"]).to eq(67890)
      expect(result["channel_id"]).to eq("12345")
      expect(result["message"]).to eq(reply)
      expect(result["response"]).to eq(response_double)
    end
  end

  describe "#update" do
    let(:strategy) { described_class.new(**options) }
    let(:channel_double) { instance_double(Discordrb::Channel) }
    let(:response_double) { instance_double(Discordrb::Message) }
    let(:message) do
      {
        "channel" => channel_double
      }
    end
    let(:reply) { {"response" => response_double} }
    let(:update_text) { "Updated message" }

    context "when file and filename are provided" do
      let(:file) { "file content" }
      let(:filename) { "test.png" }

      it "sends a file with empty caption to the channel" do
        expect(response_double).to receive(:delete).with("status message")
        expect(channel_double).to receive(:send_file).with(file, caption: "", filename: filename)

        strategy.update(message, reply, update_text, file, filename)
      end
    end

    context "when no file is provided" do
      it "edits the original response" do
        expect(response_double).to receive(:edit).with(update_text)

        strategy.update(message, reply, update_text)
      end
    end
  end

  describe "#handle_message" do
    # This is a private method, but we can test its behavior through the event handlers
    let(:strategy) { described_class.new(**options) }
    let(:event_double) { instance_double(Discordrb::Events::MessageEvent) }
    let(:user_double) { instance_double(Discordrb::User) }
    let(:channel_double) { instance_double(Discordrb::Channel) }
    let(:message_double) { instance_double(Discordrb::Message) }

    before do
      # Set up the bot user
      strategy.instance_variable_set(:@bot_user, user_double)
      allow(user_double).to receive(:id).and_return(98765)
      allow(user_double).to receive(:mention).and_return("<@98765>")
    end

    it "ignores messages from bot accounts" do
      allow(event_double).to receive(:user).and_return(user_double)
      allow(user_double).to receive(:bot_account?).and_return(true)

      # We can't easily test the private method directly, but we can check that
      # the message handler is not called by ensuring no side effects occur
      handler_called = false
      strategy.instance_variable_set(:@message_handler, proc { handler_called = true })

      strategy.send(:handle_message, event_double)

      expect(handler_called).to be false
    end

    it "processes messages that mention the bot" do
      allow(event_double).to receive(:user).and_return(user_double)
      allow(user_double).to receive(:bot_account?).and_return(false)
      allow(user_double).to receive(:id).and_return("user-123")
      allow(event_double).to receive(:message).and_return(message_double)
      allow(message_double).to receive(:content).and_return("Hello <@98765>")
      allow(message_double).to receive(:id).and_return("message-456")
      allow(message_double).to receive(:attachments).and_return([]) # Add this line
      allow(event_double).to receive(:channel).and_return(channel_double)
      allow(channel_double).to receive(:pm?).and_return(false)
      allow(channel_double).to receive(:id).and_return(123456789)

      handler_called = false
      message_data = nil
      strategy.instance_variable_set(:@message_handler, proc { |data, event|
        handler_called = true
        message_data = data
      })

      strategy.send(:handle_message, event_double)

      expect(handler_called).to be true
      expect(message_data).to be_a(Hash)
      expect(message_data["event"]).to eq("posted")
      expect(message_data["message"]).to eq("Hello <@98765>")
      expect(message_data["data"]["post"]["message"]).to eq("Hello <@98765>")
      expect(message_data["data"]["post"]["user_id"]).to eq("user-123")
      expect(message_data["data"]["post"]["channel_id"]).to eq("123456789")
      expect(message_data["data"]["post"]["id"]).to eq("message-456")
      expect(message_data["data"]["channel_type"]).to eq("O")
      expect(message_data["data"]["mentions"]).to include("98765")
    end

    it "processes messages in DMs" do
      allow(event_double).to receive(:user).and_return(user_double)
      allow(user_double).to receive(:bot_account?).and_return(false)
      allow(user_double).to receive(:id).and_return("user-123")
      allow(event_double).to receive(:message).and_return(message_double)
      allow(message_double).to receive(:content).and_return("Hello")
      allow(message_double).to receive(:id).and_return("message-456")
      allow(message_double).to receive(:attachments).and_return([]) # Add this line
      allow(event_double).to receive(:channel).and_return(channel_double)
      allow(channel_double).to receive(:pm?).and_return(true)
      allow(channel_double).to receive(:id).and_return(123456789)

      handler_called = false
      strategy.instance_variable_set(:@message_handler, proc { |data, event|
        handler_called = true
      })

      strategy.send(:handle_message, event_double)

      expect(handler_called).to be true
    end

    it "processes messages in allowed channels" do
      allow(event_double).to receive(:user).and_return(user_double)
      allow(user_double).to receive(:bot_account?).and_return(false)
      allow(user_double).to receive(:id).and_return("user-123")
      allow(event_double).to receive(:message).and_return(message_double)
      allow(message_double).to receive(:content).and_return("Hello")
      allow(message_double).to receive(:id).and_return("message-456")
      allow(message_double).to receive(:attachments).and_return([]) # Add this line
      allow(event_double).to receive(:channel).and_return(channel_double)
      allow(channel_double).to receive(:pm?).and_return(false)
      allow(channel_double).to receive(:id).and_return(123456789)

      # Set up allowed channels to include this channel
      strategy.instance_variable_set(:@discord_channels, [123456789])

      handler_called = false
      strategy.instance_variable_set(:@message_handler, proc { |data, event|
        handler_called = true
      })

      strategy.send(:handle_message, event_double)

      expect(handler_called).to be true
    end

    it "ignores messages not in allowed channels when channels are specified" do
      allow(event_double).to receive(:user).and_return(user_double)
      allow(user_double).to receive(:bot_account?).and_return(false)
      allow(user_double).to receive(:id).and_return("user-123")
      allow(event_double).to receive(:message).and_return(message_double)
      allow(message_double).to receive(:content).and_return("Hello")
      allow(message_double).to receive(:id).and_return("message-456")
      allow(message_double).to receive(:attachments).and_return([]) # Add this line
      allow(event_double).to receive(:channel).and_return(channel_double)
      allow(channel_double).to receive(:pm?).and_return(false)
      allow(channel_double).to receive(:id).and_return(999999999) # Different channel

      # Set up allowed channels that don't include this channel
      strategy.instance_variable_set(:@discord_channels, [123456789])

      handler_called = false
      strategy.instance_variable_set(:@message_handler, proc { |data, event|
        handler_called = true
      })

      strategy.send(:handle_message, event_double)

      expect(handler_called).to be false
    end
  end

  describe "#extract_mentions" do
    let(:strategy) { described_class.new(**options) }
    let(:user_double) { instance_double(Discordrb::User) }

    before do
      strategy.instance_variable_set(:@bot_user, user_double)
      allow(user_double).to receive(:id).and_return(98765)
      allow(user_double).to receive(:mention).and_return("<@98765>")
    end

    it "extracts user mentions from content" do
      content = "Hello <@12345> and <@67890>!"
      mentions = strategy.send(:extract_mentions, content)

      expect(mentions).to include("12345")
      expect(mentions).to include("67890")
      expect(mentions).not_to include("98765") # Bot not mentioned in content
    end

    it "includes bot ID when bot is mentioned" do
      content = "Hello <@98765>!"
      mentions = strategy.send(:extract_mentions, content)

      expect(mentions).to include("98765")
      # The implementation includes duplicates, so we should check for unique values
      expect(mentions.uniq).to contain_exactly("98765")
    end

    it "handles nickname mentions with !" do
      content = "Hello <@!12345>!"
      mentions = strategy.send(:extract_mentions, content)

      expect(mentions).to include("12345")
    end

    it "includes bot ID when bot is mentioned alongside other users" do
      content = "Hello <@12345> and <@98765>!"
      mentions = strategy.send(:extract_mentions, content)

      expect(mentions).to include("12345")
      expect(mentions).to include("98765")
      # The implementation includes duplicates, so we should check for unique values
      expect(mentions.uniq).to contain_exactly("12345", "98765")
    end

    it "handles multiple mentions including bot" do
      content = "<@12345> <@67890> <@98765>"
      mentions = strategy.send(:extract_mentions, content)

      expect(mentions).to include("12345")
      expect(mentions).to include("67890")
      expect(mentions).to include("98765")
      # The implementation includes duplicates, so we should check for unique values
      expect(mentions.uniq).to contain_exactly("12345", "67890", "98765")
    end
  end

  describe "#download_attached_images" do
    let(:strategy) { described_class.new(**options) }
    let(:message_data) { {"event" => "posted"} }
    let(:event_double) { instance_double(Discordrb::Events::MessageEvent) }
    let(:message_double) { instance_double(Discordrb::Message) }
    let(:attachment_double) { instance_double(Discordrb::Attachment) }
    let(:image_attachment_double) { instance_double(Discordrb::Attachment) }

    before do
      allow(event_double).to receive(:message).and_return(message_double)
      allow(strategy).to receive(:is_image_attachment?)
    end

    context "when message has no attachments" do
      before do
        allow(message_double).to receive(:attachments).and_return([])
      end

      it "does not process any attachments" do
        strategy.send(:download_attached_images, message_data, event_double)
        expect(strategy).not_to have_received(:is_image_attachment?)
        expect(message_data["attached_files"]).to be_nil
      end
    end

    context "when message has attachments" do
      before do
        allow(message_double).to receive(:attachments).and_return([attachment_double, image_attachment_double])
        allow(strategy).to receive(:is_image_attachment?).with(attachment_double).and_return(false)
        allow(strategy).to receive(:is_image_attachment?).with(image_attachment_double).and_return(true)
        allow(image_attachment_double).to receive(:url).and_return("https://example.com/image.png")
        allow(image_attachment_double).to receive(:filename).and_return("test.png")
      end

      it "collects URLs for only image attachments" do
        strategy.send(:download_attached_images, message_data, event_double)
        expect(strategy).to have_received(:is_image_attachment?).with(attachment_double)
        expect(strategy).to have_received(:is_image_attachment?).with(image_attachment_double)
        expect(message_data["attached_files"]).to eq(["https://example.com/image.png"])
      end
    end
  end

  describe "#is_image_attachment?" do
    let(:strategy) { described_class.new(**options) }
    let(:attachment_double) { instance_double(Discordrb::Attachment) }

    it "returns true for image content types" do
      allow(attachment_double).to receive(:content_type).and_return("image/png")
      result = strategy.send(:is_image_attachment?, attachment_double)
      expect(result).to be true
    end

    it "returns true for other image content types" do
      allow(attachment_double).to receive(:content_type).and_return("image/jpeg")
      result = strategy.send(:is_image_attachment?, attachment_double)
      expect(result).to be true
    end

    it "returns false for non-image content types" do
      allow(attachment_double).to receive(:content_type).and_return("application/pdf")
      result = strategy.send(:is_image_attachment?, attachment_double)
      expect(result).to be false
    end

    it "returns false when content_type is nil" do
      allow(attachment_double).to receive(:content_type).and_return(nil)
      result = strategy.send(:is_image_attachment?, attachment_double)
      expect(result).to be false
    end
  end
end
