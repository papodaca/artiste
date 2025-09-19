require "spec_helper"
require_relative "../../../config/database"

RSpec.describe CreatePresetCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) {
    double("Message",
      user_id: "test-user",
      data: {"post" => {"id" => "post-id", "channel_id" => "channel-id"}})
  }
  let(:user_settings) {
    instance_double("UserSettings",
      user_id: "test-user",
      username: "testuser")
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
          error: "Invalid format. Use: /create-preset <name> <prompt>"
        })
      end

      it "returns error for empty input" do
        result = described_class.parse("")
        expect(result).to eq({
          error: "Invalid format. Use: /create-preset <name> <prompt>"
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

    context "when preset name conflicts with parameter names" do
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      # Test all parameter names
      %w[model basesize aspect_ratio shift width height steps seed negative_prompt preset private].each do |param_name|
        context "with preset name '#{param_name}'" do
          let(:parsed_result) { {name: param_name, prompt: "test prompt"} }

          it "responds with error message about conflicting name" do
            expect(mattermost).to receive(:respond) do |msg, response|
              expect(msg).to eq(message)
              expect(response).to include("❌ Preset name '#{param_name}' conflicts with a parameter name")
            end

            command.execute
          end

          it "does not create a new preset" do
            expect { command.execute }.not_to change { Preset.count }
          end
        end
      end

      # Test shorthand parameter names
      %w[m b a S w h s n P p].each do |shorthand|
        context "with preset name '#{shorthand}'" do
          let(:parsed_result) { {name: shorthand, prompt: "test prompt"} }

          it "responds with error message about conflicting name" do
            expect(mattermost).to receive(:respond) do |msg, response|
              expect(msg).to eq(message)
              expect(response).to include("❌ Preset name '#{shorthand}' conflicts with a parameter name")
            end

            command.execute
          end

          it "does not create a new preset" do
            expect { command.execute }.not_to change { Preset.count }
          end
        end
      end
    end

    context "when preset name already exists" do
      before do
        Preset.create(
          name: "existing_preset",
          user_id: "another_user",
          prompt: "existing prompt",
          parameters: {}.to_json
        )
      end

      let(:parsed_result) { {name: "existing_preset", prompt: "new prompt"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "responds with error message about duplicate name" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ A preset named 'existing_preset' already exists")
        end

        command.execute
      end

      it "does not create a new preset" do
        expect { command.execute }.not_to change { Preset.count }
      end
    end

    context "with valid parameters" do
      let(:parsed_result) { {name: "test_preset", prompt: "a beautiful landscape --ar 16:9 --steps 20"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "creates a new preset in the database" do
        expect { command.execute }.to change { Preset.count }.by(1)
      end

      it "saves the preset with correct attributes" do
        command.execute

        preset = Preset.last
        expect(preset.name).to eq("test_preset")
        expect(preset.user_id).to eq("test-user")
        expect(preset.username).to eq("testuser")
        expect(preset.prompt).to eq("a beautiful landscape")

        params = JSON.parse(preset.parameters, symbolize_names: true)
        expect(params[:aspect_ratio]).to eq("16:9")
        expect(params[:steps]).to eq(20)
        expect(params[:width]).to eq(1344)
        expect(params[:height]).to eq(768)
      end

      it "responds with success message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("✅ Preset 'test_preset' created successfully!")
          expect(response).to include("📝 Prompt: a beautiful landscape")
          expect(response).to include("⚙️ Parameters:")
        end

        command.execute
      end
    end

    context "with complex prompt parameters" do
      let(:parsed_result) { {name: "complex_preset", prompt: "portrait of a person --model qwen --steps 30 --basesize 1328 --shift 3.1 --no glasses, hat"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      it "correctly parses all parameters" do
        command.execute

        preset = Preset.last
        params = JSON.parse(preset.parameters, symbolize_names: true)

        expect(params[:model]).to eq("qwen")
        expect(params[:steps]).to eq(30)
        expect(params[:basesize]).to eq(1328)
        expect(params[:shift]).to eq(3.1)
        expect(params[:negative_prompt]).to eq("glasses, hat")
        expect(preset.prompt).to eq("portrait of a person")
      end
    end

    context "when database save fails" do
      let(:parsed_result) { {name: "test_preset", prompt: "simple prompt"} }
      let(:command) { described_class.new(mattermost, message, parsed_result, user_settings) }

      before do
        allow_any_instance_of(Preset).to receive(:save).and_return(false)
        allow_any_instance_of(Preset).to receive_message_chain(:errors, :full_messages, :join).and_return("Validation failed")
      end

      it "responds with error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to include("❌ Failed to create preset 'test_preset'")
        end

        command.execute
      end
    end
  end

  describe "global preset availability" do
    it "allows different users to access the same preset" do
      # Create preset as one user
      preset = Preset.create(
        name: "shared_preset",
        user_id: "user1",
        prompt: "shared prompt",
        parameters: {steps: 20}.to_json
      )

      # Another user should be able to find it
      found_preset = Preset.find_by_name("shared_preset")
      expect(found_preset).to eq(preset)

      # And it should appear in user-specific queries
      user1_presets = Preset.for_user("user1")
      expect(user1_presets).to include(preset)

      user2_presets = Preset.for_user("user2")
      expect(user2_presets).to be_empty # user2 hasn't created any presets
    end

    it "prevents duplicate preset names globally" do
      Preset.create(
        name: "unique_preset",
        user_id: "user1",
        prompt: "first prompt",
        parameters: {}.to_json
      )

      expect {
        Preset.create(
          name: "unique_preset",
          user_id: "user2",
          prompt: "second prompt",
          parameters: {}.to_json
        )
      }.to raise_error(Sequel::UniqueConstraintViolation)
    end
  end
end
