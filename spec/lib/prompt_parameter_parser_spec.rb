require "spec_helper"

RSpec.describe PromptParameterParser do
  describe ".parse" do
    it "delegates to instance method" do
      parser = instance_double(PromptParameterParser)
      expect(PromptParameterParser).to receive(:new).and_return(parser)
      expect(parser).to receive(:parse).with("test prompt", "flux")
      described_class.parse("test prompt", "flux")
    end
  end

  describe ".resolve_params" do
    it "delegates to instance method" do
      parser = instance_double(PromptParameterParser)
      expect(PromptParameterParser).to receive(:new).and_return(parser)
      params = {test: "value"}
      expect(parser).to receive(:resolve_params).with(params)
      described_class.resolve_params(params)
    end
  end

  describe "#parse" do
    context "when prompt is a command (starts with /)" do
      it "calls CommandDispatcher.parse_command" do
        parser = described_class.new
        expect(CommandDispatcher).to receive(:parse_command).with("/help")
        parser.parse("/help", "flux")
      end
    end

    context "when prompt is a normal prompt" do
      it "returns default parameters with clean text" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape", "flux")

        expect(result[:model]).to eq("flux")
        expect(result[:prompt]).to eq("a beautiful landscape")
        expect(result[:width]).to eq(1024)
        expect(result[:height]).to eq(1024)
        expect(result[:steps]).to eq(2)
        expect(result[:seed]).to be_a(Integer)
        expect(result[:negative_prompt]).to eq("")
      end

      it "uses qwen defaults when model is qwen" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape", "qwen")

        expect(result[:model]).to eq("qwen")
        expect(result[:steps]).to eq(20)
        expect(result[:width]).to eq(1328)
        expect(result[:height]).to eq(1328)
        expect(result[:basesize]).to eq(1328)
        expect(result[:shift]).to eq(3.1)
      end

      it "overrides defaults with provided parameters" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --width 512 --height 768 --steps 10", "flux")

        expect(result[:width]).to eq(512)
        expect(result[:height]).to eq(768)
        expect(result[:steps]).to eq(10)
        expect(result[:prompt]).to eq("a beautiful landscape")
      end

      it "extracts model parameter and uses appropriate defaults" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --model qwen", nil)

        expect(result[:model]).to eq("qwen")
        expect(result[:width]).to eq(1328)
        expect(result[:height]).to eq(1328)
        expect(result[:steps]).to eq(20)
      end

      it "handles negative prompt" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --no ugly, bad quality", "flux")

        expect(result[:negative_prompt]).to eq("ugly, bad quality")
        expect(result[:prompt]).to eq("a beautiful landscape")
      end

      it "handles seed parameter" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --seed 12345", "flux")

        expect(result[:seed]).to eq(12345)
        expect(result[:prompt]).to eq("a beautiful landscape")
      end

      it "handles aspect ratio parameter" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --ar 16:9", "flux")

        expect(result[:aspect_ratio]).to eq("16:9")
        expect(result[:width]).to eq(1344)
        expect(result[:height]).to eq(768)
        expect(result[:prompt]).to eq("a beautiful landscape")
      end

      it "handles shift parameter for qwen model" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --model qwen --shift 2.5", "flux")

        expect(result[:model]).to eq("qwen")
        expect(result[:shift]).to eq(2.5)
      end

      it "handles basesize parameter" do
        parser = described_class.new
        result = parser.parse("a beautiful landscape --basesize 512 --ar 3:2", "flux")

        expect(result[:basesize]).to eq(512)
        expect(result[:width]).to eq(512)
        expect(result[:height]).to eq(336) # 512 * 2/3 = 341.33, rounded to nearest multiple of 8 = 336
        expect(result[:prompt]).to eq("a beautiful landscape")
      end
    end
  end

  describe "#resolve_params" do
    it "calls resolve_aspect_ratio when aspect_ratio is present" do
      parser = described_class.new
      params = {aspect_ratio: "16:9"}
      expect(parser).to receive(:resolve_aspect_ratio).with(params)
      parser.resolve_params(params)
    end

    it "does not call resolve_aspect_ratio when aspect_ratio is not present" do
      parser = described_class.new
      params = {width: 512, height: 512}
      expect(parser).not_to receive(:resolve_aspect_ratio)
      result = parser.resolve_params(params)
      expect(result).to eq(params)
    end

    it "returns the params hash" do
      parser = described_class.new
      params = {test: "value"}
      result = parser.resolve_params(params)
      expect(result).to eq(params)
      expect(result).to be(params)
    end
  end

  describe "#extract_parameters" do
    it "extracts all parameters correctly" do
      parser = described_class.new
      text = "test prompt --model flux --ar 16:9 --width 512 --height 768 --steps 10 --seed 12345 --no ugly, bad quality --shift 2.5 --basesize 1024"
      result = parser.send(:extract_parameters, text)

      expect(result[:parsed_params][:model]).to eq("flux")
      expect(result[:parsed_params][:aspect_ratio]).to eq("16:9")
      expect(result[:parsed_params][:width]).to eq(512)
      expect(result[:parsed_params][:height]).to eq(768)
      expect(result[:parsed_params][:steps]).to eq(10)
      expect(result[:parsed_params][:seed]).to eq(12345)
      expect(result[:parsed_params][:negative_prompt]).to eq("ugly, bad quality")
      expect(result[:parsed_params][:shift]).to eq(2.5)
      expect(result[:parsed_params][:basesize]).to eq(1024)
      expect(result[:clean_text]).to eq("test prompt")
    end

    it "handles multiple delete keys in set_settings command parameters" do
      parser = described_class.new
      params_string = "--ar 3:2 --steps 30 --delete aspect_ratio --delete steps"
      result = parser.send(:extract_parameters, params_string)
      delete_keys = params_string.scan(/--delete\s+(\w+)/).map { |s| s[0].to_sym }

      expect(result[:parsed_params][:aspect_ratio]).to eq("3:2")
      expect(result[:parsed_params][:steps]).to eq(30)
      expect(delete_keys).to contain_exactly(:aspect_ratio, :steps)
    end

    it "extracts shorthand parameters correctly" do
      parser = described_class.new
      text = "test prompt -m flux -a 16:9 -w 512 -h 768 -s 10 -n ugly, bad quality -S 2.5 -b 1024 -p"
      result = parser.send(:extract_parameters, text)

      expect(result[:parsed_params][:model]).to eq("flux")
      expect(result[:parsed_params][:aspect_ratio]).to eq("16:9")
      expect(result[:parsed_params][:width]).to eq(512)
      expect(result[:parsed_params][:height]).to eq(768)
      expect(result[:parsed_params][:steps]).to eq(10)
      expect(result[:parsed_params][:negative_prompt]).to eq("ugly, bad quality")
      expect(result[:parsed_params][:shift]).to eq(2.5)
      expect(result[:parsed_params][:basesize]).to eq(1024)
      expect(result[:parsed_params][:private]).to be(true)
      expect(result[:clean_text]).to eq("test prompt")
    end

    it "handles mixed shorthand and longform parameters" do
      parser = described_class.new
      text = "test prompt -m qwen --width 1024 -h 512 --steps 20 -n bad quality"
      result = parser.send(:extract_parameters, text)

      expect(result[:parsed_params][:model]).to eq("qwen")
      expect(result[:parsed_params][:width]).to eq(1024)
      expect(result[:parsed_params][:height]).to eq(512)
      expect(result[:parsed_params][:steps]).to eq(20)
      expect(result[:parsed_params][:negative_prompt]).to eq("bad quality")
      expect(result[:clean_text]).to eq("test prompt")
    end

    it "handles mixed shorthand and longform parameters with =" do
      parser = described_class.new
      text = "test prompt -m qwen --width=1024 -h 512 --steps=20 -n bad quality"
      result = parser.send(:extract_parameters, text)

      expect(result[:parsed_params][:model]).to eq("qwen")
      expect(result[:parsed_params][:width]).to eq(1024)
      expect(result[:parsed_params][:height]).to eq(512)
      expect(result[:parsed_params][:steps]).to eq(20)
      expect(result[:parsed_params][:negative_prompt]).to eq("bad quality")
      expect(result[:clean_text]).to eq("test prompt")
    end

    it "handles seed parameter (longform only)" do
      parser = described_class.new
      text = "test prompt --seed 12345"
      result = parser.send(:extract_parameters, text)

      expect(result[:parsed_params][:seed]).to eq(12345)
      expect(result[:clean_text]).to eq("test prompt")
    end
  end

  describe "#resolve_aspect_ratio" do
    it "resolves standard aspect ratios" do
      parser = described_class.new
      params = {aspect_ratio: "16:9", basesize: 1024}
      parser.send(:resolve_aspect_ratio, params)

      expect(params[:width]).to eq(1344)
      expect(params[:height]).to eq(768)
    end

    it "calculates custom aspect ratios" do
      parser = described_class.new
      params = {aspect_ratio: "2:1", basesize: 1024}
      parser.send(:resolve_aspect_ratio, params)

      expect(params[:width]).to eq(1024)
      expect(params[:height]).to eq(512)
    end

    it "uses default basesize when not specified" do
      parser = described_class.new
      params = {aspect_ratio: "3:2"}
      parser.send(:resolve_aspect_ratio, params)

      expect(params[:width]).to eq(1216)
      expect(params[:height]).to eq(810)
    end
  end

  describe "#aspect_ratio_to_dimensions" do
    it "returns standard ratios from lookup table" do
      parser = described_class.new
      width, height = parser.send(:aspect_ratio_to_dimensions, "16:9", 1024)
      expect([width, height]).to eq([1344, 768])
    end

    it "calculates custom ratios" do
      parser = described_class.new
      width, height = parser.send(:aspect_ratio_to_dimensions, "2:1", 1024)
      expect(width).to eq(1024)
      expect(height).to eq(512)
    end

    it "rounds to multiples of 8" do
      parser = described_class.new
      width, height = parser.send(:aspect_ratio_to_dimensions, "1.5:1", 1024)
      expect(width % 8).to eq(0)
      expect(height % 8).to eq(0)
    end

    it "returns default 1024x1024 for invalid ratios" do
      parser = described_class.new
      width, height = parser.send(:aspect_ratio_to_dimensions, "invalid", 1024)
      expect([width, height]).to eq([1024, 1024])
    end
  end
end
