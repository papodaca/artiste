require "spec_helper"

RSpec.describe TextCommand do
  describe ".parse" do
    it "parses a prompt into a command structure" do
      result = TextCommand.parse("Write a poem about art")
      expect(result).to eq({
        model: "Qwen/Qwen3-235B-A22B-Instruct-2507",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "strips whitespace from the prompt" do
      result = TextCommand.parse("  Write a poem about art  ")
      expect(result).to eq({
        model: "Qwen/Qwen3-235B-A22B-Instruct-2507",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "handles empty strings" do
      result = TextCommand.parse("")
      expect(result).to eq({
        model: "Qwen/Qwen3-235B-A22B-Instruct-2507",
        prompt: "",
        system_prompt: true,
        temperature: 0.7
      })
    end
  end
end

RSpec.describe CommandDispatcher do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id"}}} }
  let(:user_settings) { {theme: "dark"} }
  let(:debug_log_enabled) { false }

  describe ".execute" do
    context "when command type is :help" do
      let(:parsed_result) { {type: :help, help_text: "Help information"} }
      let(:command_instance) { instance_double(HelpCommand, execute: "Help response") }

      it "creates and executes a HelpCommand" do
        expect(HelpCommand).to receive(:new).with(mattermost, message, parsed_result, user_settings, debug_log_enabled).and_return(command_instance)
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    context "when command type is :get_settings" do
      let(:parsed_result) { {type: :get_settings} }
      let(:command_instance) { instance_double(GetSettingsCommand, execute: "Settings response") }

      it "creates and executes a GetSettingsCommand" do
        expect(GetSettingsCommand).to receive(:new).with(mattermost, message, parsed_result, user_settings, debug_log_enabled).and_return(command_instance)
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    context "when command type is :set_settings" do
      let(:parsed_result) { {type: :set_settings, settings: {theme: "light"}} }
      let(:command_instance) { instance_double(SetSettingsCommand, execute: "Settings updated") }

      it "creates and executes a SetSettingsCommand" do
        expect(SetSettingsCommand).to receive(:new).with(mattermost, message, parsed_result, user_settings, debug_log_enabled).and_return(command_instance)
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    context "when command type is :details" do
      let(:parsed_result) { {type: :details, image_name: "image.png"} }
      let(:command_instance) { instance_double(GetDetailsCommand, execute: "Details response") }

      it "creates and executes a GetDetailsCommand" do
        expect(GetDetailsCommand).to receive(:new).with(mattermost, message, parsed_result, user_settings, debug_log_enabled).and_return(command_instance)
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    context "when command type is :text" do
      let(:parsed_result) { {type: :text, prompt: "Hello, how are you?"} }
      let(:command_instance) { instance_double(TextCommand, execute: "Text response") }

      it "creates and executes a TextCommand" do
        expect(TextCommand).to receive(:new).with(mattermost, message, parsed_result, user_settings, debug_log_enabled).and_return(command_instance)
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    context "when command type is unknown" do
      let(:parsed_result) { {type: :invalid_command} }
      let(:command_instance) { instance_double(UnknownCommand, execute: "Unknown command response") }

      it "creates and executes an UnknownCommand" do
        # The parsed_result should be modified before UnknownCommand.new is called
        expect(UnknownCommand).to receive(:new) do |mm, msg, result, settings, debug|
          expect(result[:type]).to eq(:unknown_command)
          expect(result[:error]).to eq("Unknown command type: invalid_command")
          command_instance
        end
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    context "when command type is nil" do
      let(:parsed_result) { {type: nil} }
      let(:command_instance) { instance_double(UnknownCommand, execute: "Unknown command response") }

      it "creates and executes an UnknownCommand" do
        # The parsed_result should be modified before UnknownCommand.new is called
        expect(UnknownCommand).to receive(:new) do |mm, msg, result, settings, debug|
          expect(result[:type]).to eq(:unknown_command)
          expect(result[:error]).to eq("Unknown command type: ")
          command_instance
        end
        expect(command_instance).to receive(:execute)

        described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      end
    end

    it "returns the result of the command execution" do
      parsed_result = {type: :help, help_text: "Help information"}
      command_instance = instance_double(HelpCommand, execute: "Help executed successfully")

      expect(HelpCommand).to receive(:new).with(mattermost, message, parsed_result, user_settings, debug_log_enabled).and_return(command_instance)
      expect(command_instance).to receive(:execute).and_return("Help executed successfully")

      result = described_class.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
      expect(result).to eq("Help executed successfully")
    end
  end
end
