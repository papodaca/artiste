require "spec_helper"

RSpec.describe HelpCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:user_settings) { {theme: "dark"} }

  describe "#execute" do
    context "when help text is provided" do
      let(:help_text) { "Available commands:\n/set_settings - Set your default generation parameters\n/get_settings - View your current settings" }
      let(:parsed_result) { {type: :help, help_text: help_text} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with the provided help text" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq(help_text)
        end

        command.execute
      end
    end

    context "when help text is empty" do
      let(:help_text) { "" }
      let(:parsed_result) { {type: :help, help_text: help_text} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with an empty message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("")
        end

        command.execute
      end
    end

    context "when help text is nil" do
      let(:parsed_result) { {type: :help, help_text: nil} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with nil" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to be_nil
        end

        command.execute
      end
    end
  end
end
