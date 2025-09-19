require "spec_helper"
require_relative "../../../config/database"

RSpec.describe ShowPresetCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) {
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}})
  }
  let(:user_settings) { instance_double("UserSettings") }

  before do
    allow(mattermost).to receive(:respond)
    DB[:presets].delete # Clean up any test data
  end

  describe ".parse" do
    context "with valid format" do
      it "parses name correctly" do
        result = described_class.parse("test_preset")
        expect(result).to eq({
          name: "test_preset"
        })
      end

      it "strips whitespace from name" do
        result = described_class.parse("  test_preset  ")
        expect(result).to eq({
          name: "test_preset"
        })
      end
    end

    context "with invalid format" do
      it "returns error for empty input" do
        result = described_class.parse("")
        expect(result).to eq({
          error: "Invalid format. Use: /show_preset <name>"
        })
      end

      it "returns error for name with spaces" do
        result = described_class.parse("test preset")
        expect(result).to eq({
          error: "Invalid format. Use: /show_preset <name>"
        })
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

    context "when preset does not exist" do
      let(:parsed_result) { {name: "nonexistent_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about preset not found" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Preset 'nonexistent_preset' not found")
        end

        command.execute
      end
    end

    context "when preset exists" do
      let!(:existing_preset) { create(:preset, :landscape, name: "test_preset", user_id: "creator_user", username: "creator_user") }

      let(:parsed_result) { {name: "test_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "shows detailed preset information" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)

          # Check all details are included
          expect(response).to include("📋 **Preset Details: test_preset**")
          expect(response).to include("👤 **Created by:** creator_user")
          expect(response).to include("🕒 **Created at:**")
          expect(response).to include("📝 **Prompt:** beautiful mountain landscape with trees")
          expect(response).to include("⚙️ **Parameters:**")
          expect(response).to include("• Steps: 30")
          expect(response).to include("• Aspect Ratio: 16:9")
          expect(response).to include("• Model: flux")

          # Should not include delete option for non-creator
          expect(response).not_to include("🗑️ **Delete:**")
        end

        command.execute
      end
    end

    context "when preset has no parameters" do
      let!(:existing_preset) { create(:preset, name: "simple_preset", user_id: "creator_user", prompt: "simple prompt", parameters: {}.to_json) }

      let(:parsed_result) { {name: "simple_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "shows no parameters message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("• No additional parameters")
        end

        command.execute
      end
    end

    context "when user is the creator" do
      let!(:existing_preset) { create(:preset, name: "user_owned_preset", user_id: "test-user", prompt: "user's prompt", parameters: {steps: 20}.to_json) }

      let(:parsed_result) { {name: "user_owned_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "includes delete option for creator" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
        end

        command.execute
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/show_preset test_preset")
      expect(result[:type]).to eq(:show_preset)
      expect(result[:name]).to eq("test_preset")
    end
  end
end
