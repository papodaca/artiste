require "spec_helper"

RSpec.describe ComfyuiClient do
  let(:comfyui_url) { "http://localhost:8188" }
  let(:token) { "test-token" }
  let(:workflow_path) { "test_workflows" }

  describe "#initialize" do
    it "can be instantiated with required parameters" do
      expect { described_class.new(comfyui_url, token, workflow_path) }.not_to raise_error
    end

    it "can be instantiated with default workflow path" do
      expect { described_class.new(comfyui_url, token) }.not_to raise_error
    end
  end

  describe "#http_client" do
    let(:client) { described_class.new(comfyui_url, token, workflow_path) }

    it "returns an http client instance" do
      expect(client.http_client).to be_a(ComfyuiHttpClient)
    end
  end

  describe "#load_workflow_template" do
    let(:client) { described_class.new(comfyui_url, token, workflow_path) }
    let(:workflow_file) { "test_workflow.json" }

    it "is a public method" do
      expect(client).to respond_to(:load_workflow_template)
    end
  end

  describe "#create_workflow_from_template" do
    let(:client) { described_class.new(comfyui_url, token, workflow_path) }

    it "is a public method" do
      expect(client).to respond_to(:create_workflow_from_template)
    end
  end

  describe "#create_workflow_from_params" do
    let(:client) { described_class.new(comfyui_url, token, workflow_path) }

    it "is a public method" do
      expect(client).to respond_to(:create_workflow_from_params)
    end
  end

  describe "#generate_and_wait" do
    let(:client) { described_class.new(comfyui_url, token, workflow_path) }

    it "is a public method" do
      expect(client).to respond_to(:generate_and_wait)
    end
  end
end
