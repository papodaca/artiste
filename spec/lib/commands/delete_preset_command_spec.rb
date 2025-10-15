require "spec_helper"

RSpec.describe DeletePresetCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) {
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}})
  }
  let(:user_settings) {
    instance_double("UserSettings",
      user_id: "test-user")
  }

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
          error: "Invalid format. Use: /delete_preset <name>"
        })
      end

      it "returns error for name with spaces" do
        result = described_class.parse("test preset")
        expect(result).to eq({
          error: "Invalid format. Use: /delete_preset <name>"
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

      it "does not delete any presets" do
        expect { command.execute }.not_to change { Preset.count }
      end
    end

    context "when user is not the creator" do
      let!(:existing_preset) do
        Preset.create(
          name: "other_user_preset",
          user_id: "other_user",
          prompt: "some prompt",
          parameters: {}.to_json
        )
      end

      let(:parsed_result) { {name: "other_user_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with permission error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ You can only delete presets you created")
          expect(response).to include("This preset was created by other_user")
        end

        command.execute
      end

      it "does not delete the preset" do
        expect { command.execute }.not_to change { Preset.count }
      end
    end

    context "when user is the creator" do
      let!(:existing_preset) do
        Preset.create(
          name: "user_owned_preset",
          user_id: "test-user",
          prompt: "user's prompt",
          parameters: {steps: 20}.to_json
        )
      end

      let(:parsed_result) { {name: "user_owned_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "deletes the preset" do
        expect { command.execute }.to change { Preset.count }.by(-1)
        expect(Preset.find_by_name("user_owned_preset")).to be_nil
      end

      it "responds with success message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🗑️ Preset 'user_owned_preset' deleted successfully!")
        end

        command.execute
      end
    end

    context "when database delete fails" do
      let!(:existing_preset) do
        Preset.create(
          name: "problem_preset",
          user_id: "test-user",
          prompt: "problem prompt",
          parameters: {}.to_json
        )
      end

      let(:parsed_result) { {name: "problem_preset"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow_any_instance_of(Preset).to receive(:destroy).and_return(false)
        allow_any_instance_of(Preset).to receive_message_chain(:errors, :full_messages, :join).and_return("Database constraint violation")
      end

      it "responds with error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Failed to delete preset 'problem_preset'")
        end

        command.execute
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/delete_preset test_preset")
      expect(result[:type]).to eq(:delete_preset)
      expect(result[:name]).to eq("test_preset")
    end
  end
end
