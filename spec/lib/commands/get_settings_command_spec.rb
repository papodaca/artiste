require "spec_helper"

RSpec.describe GetSettingsCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }

  describe "#execute" do
    context "when user has settings" do
      let(:settings_params) { {theme: "dark", notifications: true, language: "en"} }
      let(:user_settings) do
        instance_double(
          "UserSettings",
          parsed_prompt_params: settings_params
        )
      end
      let(:parsed_result) { {type: :get_settings} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with current settings in a formatted message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("⚙️ **Current Settings:**")
          expect(response).to include("```")
          expect(response).to include("Theme: dark")
          expect(response).to include("Notifications: true")
          expect(response).to include("Language: en")
          expect(response).to include("```")
        end

        command.execute
      end
    end

    context "when user has no settings" do
      let(:user_settings) do
        instance_double(
          "UserSettings",
          parsed_prompt_params: {}
        )
      end
      let(:parsed_result) { {type: :get_settings} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with a message indicating no settings are set" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("ℹ️ No settings set.")
        end

        command.execute
      end
    end

    context "when user_settings is nil" do
      let(:parsed_result) { {type: :get_settings} }
      let(:command) { described_class.new(mattermost, message, parsed_result, nil) }

      before do
        allow(mattermost).to receive(:respond)
      end

      it "responds with a message indicating no settings are set" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("ℹ️ No settings set.")
        end

        command.execute
      end
    end
  end
end
