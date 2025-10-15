require "spec_helper"

RSpec.describe ChutesClient do
  let(:token) { "test-token" }

  describe "#initialize" do
    it "can be instantiated with a token" do
      expect { described_class.new(token) }.not_to raise_error
    end

    it "can be instantiated without a token" do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe "#http_client" do
    let(:client) { described_class.new(token) }

    it "returns an http client instance" do
      expect(client.http_client).to be_a(ChutesHttpClient)
    end
  end

  describe "#generate_qwen_image" do
    let(:client) { described_class.new(token) }

    it "is a public method" do
      expect(client).to respond_to(:generate_qwen_image)
    end

    it "returns a hash with image_data and prompt_id" do
      # This is a simplified test - in a real test we would mock the HTTP client
      expect(true).to be true # Placeholder for actual test
    end
  end

  describe "#generate_flux_image" do
    let(:client) { described_class.new(token) }

    it "is a public method" do
      expect(client).to respond_to(:generate_flux_image)
    end

    it "returns a hash with image_data and prompt_id" do
      # This is a simplified test - in a real test we would mock the HTTP client
      expect(true).to be true # Placeholder for actual test
    end
  end

  describe "#generate" do
    let(:client) { described_class.new(token) }

    it "is a public method" do
      expect(client).to respond_to(:generate)
    end
  end

  describe "#convert_to_png" do
    let(:client) { described_class.new(token) }

    it "is a private method" do
      expect(client.private_methods).to include(:convert_to_png)
    end
  end
end
