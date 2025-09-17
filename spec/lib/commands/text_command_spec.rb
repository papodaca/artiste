require "spec_helper"
require "json"

RSpec.describe TextCommand do
  let(:mattermost) { instance_double("MattermostServerStrategy") }
  let(:message) { {"data" => {"post" => {"id" => "post-id", "channel_id" => "channel-id"}}} }
  let(:parsed_result) { {model: "Qwen/Qwen3-235B-A22B-Instruct-2507", prompt: "Hello, how are you?"} }
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

    it "parses custom model names" do
      result = TextCommand.parse("--model deepseek-r1 Write a poem about art")
      expect(result).to eq({
        model: "deepseek-ai/DeepSeek-R1",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.7
      })
    end

    it "parses custom temperature" do
      result = TextCommand.parse("--temperature 0.5 Write a poem about art")
      expect(result).to eq({
        model: "Qwen/Qwen3-235B-A22B-Instruct-2507",
        prompt: "Write a poem about art",
        system_prompt: true,
        temperature: 0.5
      })
    end

    it "parses no-system" do
      result = TextCommand.parse("--no-system Write a poem about art")
      expect(result).to eq({
        model: "Qwen/Qwen3-235B-A22B-Instruct-2507",
        prompt: "Write a poem about art",
        system_prompt: false,
        temperature: 0.7
      })
    end

    it "handles model names with extra whitespace" do
      result = TextCommand.parse("--model  deepseek-r1  Write a poem about art")
      expect(result).to eq({
        model: "deepseek-ai/DeepSeek-R1",
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
      end

      it "calls the OpenAI API and responds with the generated text" do
        # Mock the OpenAI client
        mock_client = instance_double("OpenAI::Client")
        allow(OpenAI::Client).to receive(:new).and_return(mock_client)

        # Mock the chat completion stream
        # Create mock chunks that respond to the required methods
        chunk1 = double("chunk")
        allow(chunk1).to receive(:to_h).and_return({"choices" => [{"delta" => {"content" => "I'm"}}]})
        allow(chunk1).to receive(:choices).and_return([double(delta: double(content: "I'm"))])

        chunk2 = double("chunk")
        allow(chunk2).to receive(:to_h).and_return({"choices" => [{"delta" => {"content" => " doing"}}]})
        allow(chunk2).to receive(:choices).and_return([double(delta: double(content: " doing"))])

        chunk3 = double("chunk")
        allow(chunk3).to receive(:to_h).and_return({"choices" => [{"delta" => {"content" => " well"}}]})
        allow(chunk3).to receive(:choices).and_return([double(delta: double(content: " well"))])

        chunk4 = double("chunk")
        allow(chunk4).to receive(:to_h).and_return({"choices" => [{"delta" => {"content" => ", thank you"}}]})
        allow(chunk4).to receive(:choices).and_return([double(delta: double(content: ", thank you"))])

        chunk5 = double("chunk")
        allow(chunk5).to receive(:to_h).and_return({"choices" => [{"delta" => {"content" => " for asking"}}]})
        allow(chunk5).to receive(:choices).and_return([double(delta: double(content: " for asking"))])

        chunk6 = double("chunk")
        allow(chunk6).to receive(:to_h).and_return({"choices" => [{"delta" => {"content" => "!"}}]})
        allow(chunk6).to receive(:choices).and_return([double(delta: double(content: "!"))])

        mock_stream = [chunk1, chunk2, chunk3, chunk4, chunk5, chunk6]

        # Convert to a stream-like object that can be iterated over
        stream_enum = mock_stream.to_enum
        allow(mock_client).to receive(:chat).and_return(double(completions: double(stream_raw: stream_enum)))

        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)

        # Mock the update calls
        expect(mattermost).to receive(:update).with(message, reply, "I'm")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you for asking")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you for asking!")
        expect(mattermost).to receive(:update).with(message, reply, "I'm doing well, thank you for asking!")

        command.execute
      end
    end

    context "when prompt is empty" do
      let(:parsed_result) { {model: "Qwen/Qwen3-235B-A22B-Instruct-2507", prompt: ""} }

      before do
        allow(mattermost).to receive(:respond)
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
      let(:parsed_result) { {model: "Qwen/Qwen3-235B-A22B-Instruct-2507", prompt: nil} }

      before do
        allow(mattermost).to receive(:respond)
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
      end

      it "responds with an error message" do
        # Mock the OpenAI client
        mock_client = instance_double("OpenAI::Client")
        allow(OpenAI::Client).to receive(:new).and_return(mock_client)

        # Create a mock chunk that simulates an API error
        mock_chunk = double("chunk")
        allow(mock_chunk).to receive(:to_h).and_return({error: {message: "API error"}})
        allow(mock_chunk).to receive(:error).and_return(double(message: "API error"))
        allow(mock_chunk).to receive(:choices).and_return(nil)

        # Mock the chat completion stream with an error
        mock_stream = [mock_chunk]
        stream_enum = mock_stream.to_enum
        allow(mock_client).to receive(:chat).and_return(double(completions: double(stream_raw: stream_enum)))

        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)
        expect(mattermost).to receive(:update).with(message, reply, "❌ Sorry, I encountered an error while generating the text response.")

        command.execute
      end
    end

    context "when API request raises an exception" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
      end

      it "responds with an error message" do
        # Mock the OpenAI client to raise an exception
        allow(OpenAI::Client).to receive(:new).and_raise(StandardError.new("API request failed"))

        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)

        # Expect the error response
        expect(mattermost).to receive(:update).with(message, reply, "❌ Sorry, I encountered an error while generating the text response.")

        command.execute
      end
    end

    context "when API key is not configured" do
      before do
        allow(mattermost).to receive(:respond).and_return(reply)
        ENV.delete("OPENAI_API_KEY")
      end

      it "responds with an error message" do
        # Expect the initial response
        expect(mattermost).to receive(:respond).with(message, "-thinking...").and_return(reply)

        # Expect the error response
        expect(mattermost).to receive(:update).with(message, reply, "❌ Sorry, I encountered an error while generating the text response.")

        command.execute
      end
    end
  end
end
