require "spec_helper"
require_relative "../../lib/comfyui_http_client"

RSpec.describe ComfyuiHttpClient do
  let(:base_url) { "http://localhost:8188" }
  let(:token) { "test-token" }

  describe "#initialize" do
    it "can be instantiated with a base URL and token" do
      expect { described_class.new(base_url, token) }.not_to raise_error
    end

    it "can be instantiated with just a base URL" do
      expect { described_class.new(base_url) }.not_to raise_error
    end
  end

  describe "#queue_prompt" do
    let(:client) { described_class.new(base_url, token) }
    let(:workflow) { {"test" => "workflow"} }

    it "is a public method" do
      expect(client).to respond_to(:queue_prompt)
    end
  end

  describe "#get_prompt_status" do
    let(:client) { described_class.new(base_url, token) }
    let(:prompt_id) { "123" }

    it "is a public method" do
      expect(client).to respond_to(:get_prompt_status)
    end
  end

  describe "#get_prompt_queue" do
    let(:client) { described_class.new(base_url, token) }

    it "is a public method" do
      expect(client).to respond_to(:get_prompt_queue)
    end
  end

  describe "#get_image" do
    let(:client) { described_class.new(base_url, token) }
    let(:filename) { "test.png" }

    it "is a public method" do
      expect(client).to respond_to(:get_image)
    end
  end
end
