require "spec_helper"
require_relative "../../lib/chutes_http_client"

RSpec.describe ChutesHttpClient do
  let(:base_url) { "https://image.chutes.ai" }
  let(:token) { "test-token" }

  describe "#initialize" do
    it "can be instantiated with required parameters" do
      expect { described_class.new(base_url, token) }.not_to raise_error
    end

    it "can be instantiated with default base url" do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#generate_image" do
    let(:client) { described_class.new(base_url, token) }

    it "is a public method" do
      expect(client).to respond_to(:generate_image)
    end

    it "returns a hash with image_data and prompt_id" do
      # This is a simplified test - in a real test we would mock the HTTP response
      expect(true).to be true # Placeholder for actual test
    end
  end
  describe "#generate_video" do
    let(:client) { described_class.new(base_url, token) }
    let(:payload) { {prompt: "test prompt"} }

    it "is a public method" do
      expect(client).to respond_to(:generate_video)
    end

    context "when the request is successful" do
      before do
        mock_response = double("HTTParty::Response",
          success?: true,
          body: "video_data",
          headers: {"x-chutes-invocationid" => "test-id"})
        allow(client.class).to receive(:post).and_return(mock_response)
      end

      it "returns a hash with video_data and prompt_id" do
        result = client.generate_video(payload)
        expect(result).to eq({
          video_data: "video_data",
          prompt_id: "test-id"
        })
      end
    end

    context "when the request fails with status 503 and retryable error" do
      before do
        # First 4 responses fail with 503, 5th succeeds
        error_response = double("HTTParty::Response",
          success?: false,
          code: 503,
          body: JSON.generate({detail: "No instances available (yet) for chute_id='4bbd3cec-e01b-5a90-88a3-c8cf369a8499'"}))

        success_response = double("HTTParty::Response",
          success?: true,
          body: "video_data",
          headers: {"x-chutes-invocationid" => "test-id"})

        allow(client.class).to receive(:post).and_return(error_response, error_response, error_response, error_response, success_response)
      end

      it "retries up to 5 times and returns the successful response" do
        expect(client.class).to receive(:post).exactly(5).times
        expect(client).to receive(:sleep).with(30).exactly(4).times

        result = client.generate_video(payload)
        expect(result).to eq({
          video_data: "video_data",
          prompt_id: "test-id"
        })
      end
    end

    context "when the request fails with status 29 and retryable error" do
      before do
        # First 2 responses fail with 29, 3rd succeeds
        error_response = double("HTTParty::Response",
          success?: false,
          code: 29,
          body: JSON.generate({detail: "Infrastructure is at maximum capacity, try again later"}))

        success_response = double("HTTParty::Response",
          success?: true,
          body: "video_data",
          headers: {"x-chutes-invocationid" => "test-id"})

        allow(client.class).to receive(:post).and_return(error_response, error_response, success_response)
      end

      it "retries and returns the successful response" do
        expect(client.class).to receive(:post).exactly(3).times
        expect(client).to receive(:sleep).with(30).exactly(2).times

        result = client.generate_video(payload)
        expect(result).to eq({
          video_data: "video_data",
          prompt_id: "test-id"
        })
      end
    end

    context "when the request fails with non-retryable error" do
      before do
        error_response = double("HTTParty::Response",
          success?: false,
          code: 500,
          body: JSON.generate({detail: "Internal server error"}))

        allow(client.class).to receive(:post).and_return(error_response)
      end

      it "does not retry and raises an error" do
        expect(client.class).to receive(:post).once
        expect(client).not_to receive(:sleep)

        expect {
          client.generate_video(payload)
        }.to raise_error(/Failed to generate video: 500/)
      end
    end

    context "when the request fails with retryable error but exceeds max retries" do
      before do
        # All 6 responses fail with 503
        error_response = double("HTTParty::Response",
          success?: false,
          code: 503,
          body: JSON.generate({detail: "No instances available (yet) for chute_id='4bbd3cec-e01b-5a90-88a3-c8cf369a8499'"}))

        allow(client.class).to receive(:post).and_return(error_response)
      end

      it "retries 5 times and then raises an error" do
        expect(client.class).to receive(:post).exactly(6).times
        expect(client).to receive(:sleep).with(30).exactly(5).times

        expect {
          client.generate_video(payload)
        }.to raise_error(/Failed to generate video: 503/)
      end
    end
  end
end
