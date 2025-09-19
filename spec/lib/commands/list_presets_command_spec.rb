require "spec_helper"
require_relative "../../../config/database"

RSpec.describe ListPresetsCommand do
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

  describe "#execute" do
    context "when no presets exist" do
      let(:command) { described_class.new(mattermost, message, {}, user_settings) }

      it "responds with no presets message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("ℹ️ No presets available")
          expect(response).to include("Use `/create_preset` to create one")
        end

        command.execute
      end
    end

    context "when presets exist" do
      before do
        create(:preset, :landscape, name: "landscape_preset", user_id: "user1", username: "user1",
          prompt: "a beautiful mountain landscape with trees and rivers")
        create(:preset, name: "portrait_preset", user_id: "user2", username: "user2",
          prompt: "portrait of a person with detailed facial features",
          parameters: {steps: 30, width: 1024, height: 1024, model: "qwen"}.to_json)
        create(:preset, name: "simple_preset", user_id: "user3", username: "user3",
          prompt: "simple test prompt", parameters: {}.to_json)
      end

      let(:command) { described_class.new(mattermost, message, {}, user_settings) }

      it "responds with list of all presets" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)

          # Check header
          expect(response).to include("📋 **Available Presets:**")

          # Check each preset is listed
          expect(response).to include("landscape_preset")
          expect(response).to include("portrait_preset")
          expect(response).to include("simple_preset")

          # Check user info
          expect(response).to include("👤 Created by: user1")
          expect(response).to include("👤 Created by: user2")
          expect(response).to include("👤 Created by: user3")

          # Check prompt truncation
          expect(response).to include("a beautiful mountain landscape with trees and rivers".truncate(50))
          expect(response).to include("portrait of a person with detailed facial features".truncate(50))

          # Check parameters display
          expect(response).to include("30 steps")
          expect(response).to include("16:9")
          expect(response).to include("flux")
          expect(response).to include("1024x1024")
          expect(response).to include("qwen")
        end

        command.execute
      end

      it "orders presets by name" do
        expect(mattermost).to receive(:respond) do |msg, response|
          # Check order: landscape_preset, portrait_preset, simple_preset
          landscape_index = response.index("landscape_preset")
          portrait_index = response.index("portrait_preset")
          simple_index = response.index("simple_preset")

          expect(landscape_index).to be < portrait_index
          expect(portrait_index).to be < simple_index
        end

        command.execute
      end
    end

    context "when database error occurs" do
      let(:command) { described_class.new(mattermost, message, {}, user_settings) }

      before do
        allow(Preset).to receive(:order).and_raise(Sequel::DatabaseError, "Database connection failed")
      end

      it "responds with error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Error listing presets")
          expect(response).to include("Database connection failed")
        end

        command.execute
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/list_presets")
      expect(result[:type]).to eq(:list_presets)
    end

    it "does not require parameters" do
      result = CommandDispatcher.parse_command("/list_presets")
      expect(result.keys).to eq([:type])
    end

    it "ignores extra parameters gracefully" do
      result = CommandDispatcher.parse_command("/list_presets extra stuff")
      expect(result[:type]).to eq(:list_presets)
    end
  end
end
