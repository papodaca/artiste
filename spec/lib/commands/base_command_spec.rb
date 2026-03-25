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
  let(:command) { test_command_class.new(mattermost, message, parsed_result, user_settings) }

  describe "#initialize" do
    it "sets mattermost instance variable" do
      expect(command.server).to eq(mattermost)
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
      let(:command) { test_command_class.new(mattermost, message, nil, user_settings) }

      it "sets parsed_result to nil" do
        expect(command.parsed_result).to be_nil
      end
    end

    context "when user_settings is not provided" do
      let(:command) { test_command_class.new(mattermost, message, parsed_result, nil) }

      it "sets user_settings to nil" do
        expect(command.user_settings).to be_nil
      end
    end
  end

  describe "#execute" do
    it "raises NotImplementedError" do
      base_command = described_class.new(mattermost, message, nil, nil)
      expect do
        base_command.execute
      end.to raise_error(NotImplementedError, "Subclasses must implement the execute method")
    end

    it "can be overridden in subclasses" do
      expect(command.execute).to eq("Test execution")
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
