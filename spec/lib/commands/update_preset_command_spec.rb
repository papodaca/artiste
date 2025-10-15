require "spec_helper"

RSpec.describe UpdatePresetCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) {
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}})
  }
  let(:user_settings) {
    instance_double("UserSettings",
      user_id: "original_user")
  }

  before do
    allow(mattermost).to receive(:respond)
    DB[:presets].delete # Clean up any test data
  end

  describe ".parse" do
    context "with valid format" do
      it "parses name and prompt correctly" do
        result = described_class.parse("test_preset a beautiful landscape --ar 16:9")
        expect(result).to eq({
          name: "test_preset",
          prompt: "a beautiful landscape --ar 16:9"
        })
      end

      it "handles prompts with multiple parameters" do
        result = described_class.parse("sunset_scene sunset over mountains --steps 25 --model flux --width 1024")
        expect(result).to eq({
          name: "sunset_scene",
          prompt: "sunset over mountains --steps 25 --model flux --width 1024"
        })
      end
    end

    context "with invalid format" do
      it "returns error for missing prompt" do
        result = described_class.parse("test_preset")
        expect(result).to eq({
          error: "Invalid format. Use: /update_preset <name> <prompt>"
        })
      end

      it "returns error for empty input" do
        result = described_class.parse("")
        expect(result).to eq({
          error: "Invalid format. Use: /update_preset <name> <prompt>"
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
      let(:parsed_result) { {name: "nonexistent_preset", prompt: "new prompt"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about preset not found" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Preset 'nonexistent_preset' not found")
          expect(response).to include("Use `/create_preset` to create it first")
        end

        command.execute
      end

      it "does not create a new preset" do
        expect { command.execute }.not_to change { Preset.count }
      end
    end

    context "with valid parameters and existing preset" do
      let!(:existing_preset) do
        Preset.create(
          name: "test_preset",
          user_id: "original_user",
          prompt: "original prompt",
          parameters: {steps: 10, width: 1024, height: 1024}.to_json
        )
      end

      let(:parsed_result) { {name: "test_preset", prompt: "updated beautiful landscape --ar 16:9 --steps 20"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "updates the existing preset" do
        expect { command.execute }.not_to change { Preset.count }

        preset = Preset.find_by_name("test_preset")
        expect(preset.prompt).to eq("updated beautiful landscape")

        params = JSON.parse(preset.parameters, symbolize_names: true)
        expect(params[:aspect_ratio]).to eq("16:9")
        expect(params[:steps]).to eq(20)
        expect(params[:width]).to eq(1344)
        expect(params[:height]).to eq(768)

        # User ID should remain unchanged
        expect(preset.user_id).to eq("original_user")
      end

      it "responds with success message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("✅ Preset 'test_preset' updated successfully!")
          expect(response).to include("📝 New prompt: updated beautiful landscape")
          expect(response).to include("⚙️ New parameters:")
        end

        command.execute
      end
    end

    context "when database save fails" do
      let!(:existing_preset) do
        Preset.create(
          name: "test_preset",
          user_id: "original_user",
          prompt: "original prompt",
          parameters: {}.to_json
        )
      end

      let(:parsed_result) { {name: "test_preset", prompt: "updated prompt"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow_any_instance_of(Preset).to receive(:save).and_return(false)
        allow_any_instance_of(Preset).to receive_message_chain(:errors, :full_messages, :join).and_return("Validation failed")
      end

      it "responds with error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Failed to update preset 'test_preset'")
        end

        command.execute
      end
    end

    context "with complex prompt parameters update" do
      let!(:existing_preset) do
        Preset.create(
          name: "complex_preset",
          user_id: "original_user",
          prompt: "old prompt",
          parameters: {steps: 10, model: "flux"}.to_json
        )
      end

      let(:parsed_result) { {name: "complex_preset", prompt: "portrait of a person --model qwen --steps 30 --basesize 1328 --shift 3.1 --no glasses, hat"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "correctly updates all parameters" do
        command.execute

        preset = Preset.find_by_name("complex_preset")
        params = JSON.parse(preset.parameters, symbolize_names: true)

        expect(params[:model]).to eq("qwen")
        expect(params[:steps]).to eq(30)
        expect(params[:basesize]).to eq(1328)
        expect(params[:shift]).to eq(3.1)
        expect(params[:negative_prompt]).to eq("glasses, hat")
        expect(preset.prompt).to eq("portrait of a person")

        # Qwen model with basesize will automatically set width and height
        expect(params[:width]).to eq(1328)
        expect(params[:height]).to eq(1328)

        # Should not have old flux-specific parameters
        expect(params).not_to have_key(:aspect_ratio)
      end
    end
  end

  describe "command parsing" do
    it "is registered in CommandDispatcher" do
      result = CommandDispatcher.parse_command("/update_preset test_preset prompt")
      expect(result[:type]).to eq(:update_preset)
      expect(result[:name]).to eq("test_preset")
      expect(result[:prompt]).to eq("prompt")
    end
  end
end
