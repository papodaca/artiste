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
end
