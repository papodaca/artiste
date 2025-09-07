require "spec_helper"
require_relative "../../../lib/commands/unknown_command"

describe UnknownCommand do
  let(:server_strategy) { instance_double("MattermostServerStrategy") }
  let(:parsed_result) { {error: "Unknown command"} }
  let(:message) { {channel_id: "test_channel"} }
  let(:user_settings) { nil }
  let(:command) { UnknownCommand.new(server_strategy, message, parsed_result, user_settings) }

  describe "#execute" do
    it "logs handling of unknown command" do
      expect(command).to receive(:debug_log).with("Handling unknown command")
      expect(command).to receive(:debug_log).with("Unknown command error: Unknown command")
      expect(server_strategy).to receive(:respond).with(message, "❌ Unknown command")

      command.execute
    end

    context "when parsed_result contains a specific error message" do
      let(:parsed_result) { {error: "Command not found: /invalid"} }

      it "uses the specific error message" do
        expect(command).to receive(:debug_log).with("Handling unknown command")
        expect(command).to receive(:debug_log).with("Unknown command error: Command not found: /invalid")
        expect(server_strategy).to receive(:respond).with(message, "❌ Command not found: /invalid")

        command.execute
      end
    end

    context "when parsed_result does not contain an error message" do
      let(:parsed_result) { {} }

      it "uses a default error message" do
        expect(command).to receive(:debug_log).with("Handling unknown command")
        expect(command).to receive(:debug_log).with("Unknown command error: Unknown command")
        expect(server_strategy).to receive(:respond).with(message, "❌ Unknown command")

        command.execute
      end
    end
  end
end
