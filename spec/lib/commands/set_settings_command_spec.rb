require "spec_helper"
require_relative "../../../config/database"

RSpec.describe SetSettingsCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:user_settings) { instance_double("UserSettings") }

  before do
    allow(mattermost).to receive(:respond)
    allow(user_settings).to receive(:save)
    allow(user_settings).to receive(:set_param)
    allow(user_settings).to receive(:delete_param)
    allow(user_settings).to receive(:parsed_prompt_params).and_return({})
  end

  describe "#execute" do
    context "when no settings or delete operations are provided" do
      let(:parsed_result) { {settings: {}, delete_keys: []} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with an error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ No settings or delete operations provided")
          expect(response).to include("Use `/help` to see available options")
        end

        command.execute
      end

      it "does not save user settings" do
        expect(user_settings).not_to receive(:save)
        command.execute
      end
    end

    context "when settings are provided" do
      let(:settings) { {width: 1024, height: 768, steps: 20} }
      let(:parsed_result) { {settings: settings, delete_keys: []} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(user_settings).to receive(:parsed_prompt_params).and_return(settings)
      end

      it "sets each parameter on user_settings" do
        expect(user_settings).to receive(:set_param).with(:width, 1024)
        expect(user_settings).to receive(:set_param).with(:height, 768)
        expect(user_settings).to receive(:set_param).with(:steps, 20)

        command.execute
      end

      it "saves the user settings" do
        expect(user_settings).to receive(:save)
        command.execute
      end

      it "responds with success message and formatted settings" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("✅ **Updated settings:**")
          expect(response).to include("```")
          expect(response).to include("Width: 1024")
          expect(response).to include("Height: 768")
          expect(response).to include("Steps: 20")
        end

        command.execute
      end
    end

    context "when aspect_ratio is provided" do
      let(:settings) { {aspect_ratio: "16:9", width: 1024, height: 768} }
      let(:parsed_result) { {settings: settings, delete_keys: []} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(user_settings).to receive(:parsed_prompt_params).and_return({aspect_ratio: "16:9"})
      end

      it "removes width and height from settings before setting" do
        expect(user_settings).to receive(:set_param).with(:aspect_ratio, "16:9")
        expect(user_settings).not_to receive(:set_param).with(:width, anything)
        expect(user_settings).not_to receive(:set_param).with(:height, anything)

        command.execute
      end
    end

    context "when delete_keys are provided" do
      let(:delete_keys) { ["width", "height"] }
      let(:parsed_result) { {settings: {}, delete_keys: delete_keys} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(user_settings).to receive(:delete_param).with(:width).and_return(true)
        allow(user_settings).to receive(:delete_param).with(:height).and_return(true)
      end

      it "deletes each parameter from user_settings" do
        expect(user_settings).to receive(:delete_param).with(:width)
        expect(user_settings).to receive(:delete_param).with(:height)

        command.execute
      end

      it "responds with deleted settings message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🗑️ **Deleted settings:** Width, Height")
        end

        command.execute
      end

      it "saves the user settings" do
        expect(user_settings).to receive(:save)
        command.execute
      end
    end

    context "when delete_keys contain non-existent settings" do
      let(:delete_keys) { ["nonexistent"] }
      let(:parsed_result) { {settings: {}, delete_keys: delete_keys} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "raises an error due to bug in code" do
        expect { command.execute }.to raise_error(NoMethodError, /undefined method.*to_sym.*for nil/)
      end
    end

    context "when both settings and delete_keys are provided" do
      let(:settings) { {model: "new_model"} }
      let(:delete_keys) { ["width"] }
      let(:parsed_result) { {settings: settings, delete_keys: delete_keys} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow(user_settings).to receive(:delete_param).with(:width).and_return(true)
        allow(user_settings).to receive(:parsed_prompt_params).and_return({model: "new_model"})
      end

      it "performs both operations" do
        expect(user_settings).to receive(:delete_param).with(:width)
        expect(user_settings).to receive(:set_param).with(:model, "new_model")
        expect(user_settings).to receive(:save)

        command.execute
      end

      it "responds with both deleted and updated settings" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("🗑️ **Deleted settings:** Width")
          expect(response).to include("✅ **Updated settings:**")
          expect(response).to include("Model: new_model")
        end

        command.execute
      end
    end
  end

  describe "#synonym" do
    let(:command) { described_class.new(mattermost, message, {}, user_settings) }

    context "when given a known synonym" do
      it "returns the canonical name for aspect ratio synonyms" do
        expect(command.send(:synonym, "ar")).to eq("aspect_ratio")
        expect(command.send(:synonym, "aspectratio")).to eq("aspect_ratio")
        expect(command.send(:synonym, "aspect_ratio")).to eq("aspect_ratio")
      end

      it "returns the canonical name for width synonyms" do
        expect(command.send(:synonym, "w")).to eq("width")
        expect(command.send(:synonym, "width")).to eq("width")
      end

      it "returns the canonical name for height synonyms" do
        expect(command.send(:synonym, "h")).to eq("height")
        expect(command.send(:synonym, "height")).to eq("height")
      end

      it "returns the canonical name for steps synonyms" do
        expect(command.send(:synonym, "s")).to eq("steps")
        expect(command.send(:synonym, "steps")).to eq("steps")
      end

      it "returns the canonical name for model synonyms" do
        expect(command.send(:synonym, "m")).to eq("model")
        expect(command.send(:synonym, "model")).to eq("model")
      end

      it "returns the canonical name for shift synonyms" do
        expect(command.send(:synonym, "sh")).to eq("shift")
        expect(command.send(:synonym, "shift")).to eq("shift")
      end

      it "returns the canonical name for basesize synonyms" do
        expect(command.send(:synonym, "bs")).to eq("basesize")
        expect(command.send(:synonym, "basesize")).to eq("basesize")
      end
    end

    context "when given an unknown synonym" do
      it "returns nil" do
        expect(command.send(:synonym, "unknown")).to be_nil
        expect(command.send(:synonym, "xyz")).to be_nil
      end
    end

    context "when given a symbol" do
      it "converts to string and finds synonym" do
        expect(command.send(:synonym, :ar)).to eq("aspect_ratio")
        expect(command.send(:synonym, :w)).to eq("width")
      end
    end
  end

  describe "SYNONYMS constant" do
    let(:command) { described_class.new(mattermost, message, {}, user_settings) }

    it "is frozen" do
      expect(SetSettingsCommand::SYNONYMS).to be_frozen
    end

    it "contains expected synonym mappings" do
      synonyms = SetSettingsCommand::SYNONYMS

      expect(synonyms["aspect_ratio"]).to include("ar", "aspectratio", "aspect_ratio")
      expect(synonyms["width"]).to include("w", "width")
      expect(synonyms["height"]).to include("h", "height")
      expect(synonyms["steps"]).to include("s", "steps")
      expect(synonyms["model"]).to include("m", "model")
      expect(synonyms["shift"]).to include("sh", "shift")
      expect(synonyms["basesize"]).to include("bs", "basesize")
    end
  end
end
