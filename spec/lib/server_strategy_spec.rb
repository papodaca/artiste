require "spec_helper"

RSpec.describe ServerStrategy do
  let(:options) { {test: "value"} }

  describe "#initialize" do
    it "raises NOT IMPLIMENTED error" do
      expect { described_class.new(options) }.to raise_error(NotImplementedError)
    end
  end

  describe "#connect" do
    let(:strategy) { described_class.allocate }

    it "raises NOT IMPLIMENTED error" do
      expect { strategy.connect }.to raise_error(NotImplementedError)
    end

    it "accepts a block parameter" do
      expect { |b| strategy.connect(&b) }.to raise_error(NotImplementedError)
    end
  end

  describe "#respond" do
    let(:strategy) { described_class.allocate }
    let(:message) { "test message" }
    let(:reply) { "test reply" }

    it "raises NOT IMPLIMENTED error" do
      expect { strategy.respond(message, reply) }.to raise_error(NotImplementedError)
    end
  end

  describe "#update" do
    let(:strategy) { described_class.allocate }
    let(:message) { "test message" }
    let(:reply) { "test reply" }
    let(:update) { "test update" }

    it "raises NOT IMPLIMENTED error" do
      expect { strategy.update(message, reply, update) }.to raise_error(NotImplementedError)
    end
  end
end
