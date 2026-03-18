require "spec_helper"

RSpec.describe TextCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:parsed_result) { {model: "Qwen/Qwen3.5-397B-A17B-TEE", prompt: "Hello, how are you?"} }
  let(:user_settings) { nil }
  let(:command) { described_class.new(mattermost, message, parsed_result, user_settings, false) }
  let(:reply) { {"id" => "reply-id"} }

  before do
    # Set environment variables for testing
    ENV["OPENAI_API_KEY"] = "test-api-key"
    ENV["OPENAI_API_URL"] = "https://api.openai.com/v1"
    ENV["OPENAI_MODEL"] = "gpt-3.5-turbo"
  end

  after do
    # Clean up environment variables
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("OPENAI_API_URL")
    ENV.delete("OPENAI_MODEL")
  end

  describe "::parse" do
    it "parses a prompt into a command structure" do
      result = TextCommand.parse("Write a poem about art")
      expect(result).to eq({
        model: "Qwen/Qwen3.5-397B-A17B-TEE",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "strips whitespace from the prompt" do
      result = TextCommand.parse("  Write a poem about art  ")
      expect(result).to eq({
        model: "Qwen/Qwen3.5-397B-A17B-TEE",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "handles empty strings" do
      result = TextCommand.parse("")
      expect(result).to eq({
        model: "Qwen/Qwen3.5-397B-A17B-TEE",
        prompt: "",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "parses custom model names" do
      result = TextCommand.parse("--model deepseek-r1 Write a poem about art")
      expect(result).to eq({
        model: "deepseek-ai/DeepSeek-R1-0528-TEE",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "parses custom temperature" do
      result = TextCommand.parse("--temperature 0.5 Write a poem about art")
      expect(result).to eq({
        model: "Qwen/Qwen3.5-397B-A17B-TEE",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.5
      })
    end

    it "parses no-system" do
      result = TextCommand.parse("--no-system Write a poem about art")
      expect(result).to eq({
        model: "Qwen/Qwen3.5-397B-A17B-TEE",
        prompt: "Write a poem about art",
        system_prompt: false,
        temperature: 0.7
      })
    end

    it "handles model names with extra whitespace" do
      result = TextCommand.parse("--model  deepseek-r1  Write a poem about art")
      expect(result).to eq({
        model: "deepseek-ai/DeepSeek-R1-0528-TEE",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end
  end

  describe "#execute" do
    context "when prompt is provided" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY_ENV").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_key")
      end

      it "calls the OpenAI API and responds with the generated text" do
        mock_client = instance_double("OpenAI::Client")
        allow(OpenAI::Client).to receive(:new).and_return(mock_client)

        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)

        expect(mattermost).to receive(:update).with(message, reply, "I'm")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you for asking")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you for asking!")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you for asking!")

        allow(mock_client).to receive(:chat) do |args|
          stream_proc = args[:parameters][:stream]
          ["I'm", " doing", " well", ", thank you", " for asking", "!"].each do |content|
            chunk = {"choices" => [{"delta" => {"content" => content}}]}
            stream_proc.call(chunk, nil)
          end
        end

        command.execute
      end
    end

    context "when prompt is empty" do
      let(:parsed_result) { {model: "Qwen/Qwen3.5-397B-A17B-TEE", prompt: ""} }

      before do
        allow(mattermost).to receive(:respond)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY_ENV").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_key")
      end

      it "responds with an error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("❌ Please provide a prompt for the text command.")
        end

        command.execute
      end
    end

    context "when prompt is nil" do
      let(:parsed_result) { {model: "Qwen/Qwen3.5-397B-A17B-TEE", prompt: nil} }

      before do
        allow(mattermost).to receive(:respond)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY_ENV").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_key")
      end

      it "responds with an error message" do
        expect(mattermost).to receive(:respond) do |msg, response|
          expect(msg).to eq(message)
          expect(response).to eq("❌ Please provide a prompt for the text command.")
        end

        command.execute
      end
    end

    context "when API request fails with an error response" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY_ENV").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_key")
      end

      it "responds with an error message" do
        mock_client = instance_double("OpenAI::Client")
        allow(OpenAI::Client).to receive(:new).and_return(mock_client)

        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)
        expect(mattermost).to receive(:update).with(message, reply,
          "❌ Sorry, I encountered an error while generating the text response.")

        allow(mock_client).to receive(:chat) do |args|
          stream_proc = args[:parameters][:stream]
          error_chunk = {error: {message: "API error"}}
          mock_chunk = Struct.new(:to_h, :error).new(error_chunk, Struct.new(:message).new("API error"))
          stream_proc.call(mock_chunk, nil)
        end

        command.execute
      end
    end

    context "when API request raises an exception" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY_ENV").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("test_key")
      end

      it "responds with an error message" do
        allow(OpenAI::Client).to receive(:new).and_raise(StandardError.new("API request failed"))

        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)

        expect(mattermost).to receive(:update).with(message, reply,
          "❌ Sorry, I encountered an error while generating the text response.")

        command.execute
      end
    end

    context "when API key is not configured" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        ENV.delete("OPENAI_API_KEY")
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY_ENV").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_URL").and_return(nil)
        allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return(nil)
      end

      it "responds with an error message" do
        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)

        # Expect the error response
        expect(mattermost).to receive(:update).with(message, reply,
          "❌ Sorry, I encountered an error while generating the text response.")

        command.execute
      end
    end
  end
end
