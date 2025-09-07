require "spec_helper"

RSpec.describe BaseCommand do
  # Create a test subclass since BaseCommand is abstract
  let(:test_command_class) do
    Class.new(BaseCommand) do
      def execute
        "Test execution"
      end
    end
  end

  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id"}}} }
  let(:parsed_result) { {type: :test_command} }
  let(:user_settings) { {theme: "dark", notifications: true} }
  let(:command) { test_command_class.new(mattermost, message, parsed_result, user_settings, false) }

  describe "#initialize" do
    it "sets mattermost instance variable" do
      expect(command.mattermost).to eq(mattermost)
    end

    it "sets message instance variable" do
      expect(command.message).to eq(message)
    end

    it "sets parsed_result instance variable" do
      expect(command.parsed_result).to eq(parsed_result)
    end

    it "sets user_settings instance variable" do
      expect(command.user_settings).to eq(user_settings)
    end

    context "when parsed_result is not provided" do
      let(:command) { test_command_class.new(mattermost, message, nil, user_settings, false) }

      it "sets parsed_result to nil" do
        expect(command.parsed_result).to be_nil
      end
    end

    context "when user_settings is not provided" do
      let(:command) { test_command_class.new(mattermost, message, parsed_result, nil, false) }

      it "sets user_settings to nil" do
        expect(command.user_settings).to be_nil
      end
    end
  end

  describe "#execute" do
    it "raises NotImplementedError" do
      base_command = described_class.new(mattermost, message, nil, nil, false)
      expect { base_command.execute }.to raise_error(NotImplementedError, "Subclasses must implement the execute method")
    end

    it "can be overridden in subclasses" do
      expect(command.execute).to eq("Test execution")
    end
  end

  describe "#debug_log" do
    let(:debug_message) { "This is a debug message" }

    context "when debug_log_enabled is true" do
      let(:command) { test_command_class.new(mattermost, message, parsed_result, user_settings, true) }

      it "outputs debug message to stdout with [DEBUG] prefix" do
        expect { command.send(:debug_log, debug_message) }.to output("[DEBUG] #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} - #{debug_message}\n").to_stdout
      end
    end

    context "when debug_log_enabled is false" do
      let(:command) { test_command_class.new(mattermost, message, parsed_result, user_settings, false) }

      it "does not output anything" do
        expect { command.send(:debug_log, debug_message) }.not_to output.to_stdout
      end
    end

    context "when debug_log_enabled is not provided (defaults to false)" do
      let(:command) { test_command_class.new(mattermost, message, parsed_result, user_settings) }

      it "does not output anything" do
        expect { command.send(:debug_log, debug_message) }.not_to output.to_stdout
      end
    end
  end

  describe "#print_settings" do
    let(:output) { [] }
    let(:settings) { {theme: "dark", notifications: true, language: "en"} }

    it "formats settings in a code block" do
      command.send(:print_settings, output, settings)
      expect(output).to eq(["```", "Theme: dark", "Notifications: true", "Language: en", "```"])
    end

    context "when settings is empty" do
      let(:settings) { {} }

      it "only outputs the code block markers" do
        command.send(:print_settings, output, settings)
        expect(output).to eq(["```", "```"])
      end
    end
  end
end
