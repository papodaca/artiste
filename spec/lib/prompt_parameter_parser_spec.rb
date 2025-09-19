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

      context "with preset parameter" do
        before(:all) do
          DB[:presets].delete
          create(:preset, :landscape)
          create(:preset, :params_only)
        end

        it "applies preset parameters and appends preset prompt" do
          parser = described_class.new
          result = parser.parse("a sunset scene --preset landscape_preset --steps 25", "flux")

          expect(result[:steps]).to eq(25) # Should override preset value
          expect(result[:aspect_ratio]).to eq("16:9") # Should use preset value
          expect(result[:model]).to eq("flux") # Should use preset value
          expect(result[:width]).to eq(1344) # Should be calculated from aspect ratio
          expect(result[:height]).to eq(768) # Should be calculated from aspect ratio
          expect(result[:prompt]).to eq("a sunset scene beautiful mountain landscape with trees")
        end

        it "only applies preset parameters that aren't already specified" do
          parser = described_class.new
          result = parser.parse("a scene --preset landscape_preset --model qwen --ar 1:1", "flux")

          expect(result[:model]).to eq("qwen") # Should override preset
          expect(result[:aspect_ratio]).to eq("1:1") # Should override preset
          expect(result[:steps]).to eq(30) # Should use preset value since not overridden
          expect(result[:width]).to eq(1328) # From qwen defaults
          expect(result[:height]).to eq(1328) # From qwen defaults
        end

        it "handles non-existent preset gracefully" do
          parser = described_class.new
          result = parser.parse("a scene --preset nonexistent_preset --steps 20", "flux")

          expect(result[:steps]).to eq(20) # Should use specified value
          expect(result[:prompt]).to eq("a scene") # Should not append anything
        end

        it "handles preset with empty prompt" do
          parser = described_class.new
          result = parser.parse("custom prompt --preset params_only_preset", "flux")

          expect(result[:steps]).to eq(40)
          expect(result[:width]).to eq(800)
          expect(result[:height]).to eq(600)
          expect(result[:prompt]).to eq("custom prompt") # Should not append empty prompt
        end

        it "extracts preset parameter from text" do
          parser = described_class.new
          result = parser.send(:extract_parameters, "test prompt --preset my_preset --steps 20")

          expect(result[:parsed_params][:preset]).to eq("my_preset")
          expect(result[:parsed_params][:steps]).to eq(20)
          expect(result[:clean_text]).to eq("test prompt")
        end

        it "handles shorthand preset parameter" do
          parser = described_class.new
          result = parser.send(:extract_parameters, "test prompt -P my_preset --steps 20")

          expect(result[:parsed_params][:preset]).to eq("my_preset")
          expect(result[:parsed_params][:steps]).to eq(20)
          expect(result[:clean_text]).to eq("test prompt")
        end

        context "with direct preset name syntax (--<preset_name>)" do
          before(:all) do
            # Ensure the preset exists for testing
            create(:preset, :vibrant_colors) unless Preset.find_by_name("vibrant_colors")
          end

          it "extracts direct preset name and applies parameters" do
            parser = described_class.new
            result = parser.parse("landscape scene --vibrant_colors --width 800", "flux")

            expect(result[:steps]).to eq(25) # From preset
            expect(result[:model]).to eq("flux") # From preset
            expect(result[:width]).to eq(800) # From user parameter (overrides any preset width)
            expect(result[:prompt]).to eq("landscape scene vibrant and colorful style")
          end

          it "removes direct preset name from clean text" do
            parser = described_class.new
            result = parser.send(:extract_parameters, "landscape scene --vibrant_colors --width 800")

            expect(result[:parsed_params][:preset]).to eq("vibrant_colors")
            expect(result[:parsed_params][:width]).to eq(800)
            expect(result[:clean_text]).to eq("landscape scene")
          end

          it "ignores --<word> patterns that are regular parameters" do
            parser = described_class.new
            result = parser.send(:extract_parameters, "test --width 800 --height 600")

            expect(result[:parsed_params][:preset]).to be_nil
            expect(result[:parsed_params][:width]).to eq(800)
            expect(result[:parsed_params][:height]).to eq(600)
            expect(result[:clean_text]).to eq("test")
          end

          it "ignores --<word> patterns that don't match existing presets" do
            parser = described_class.new
            result = parser.send(:extract_parameters, "test --nonexistent_preset --width 800")

            expect(result[:parsed_params][:preset]).to be_nil
            expect(result[:parsed_params][:width]).to eq(800)
            expect(result[:clean_text]).to eq("test --nonexistent_preset")
          end

          it "handles multiple direct preset names (uses first one found)" do
            # Create another preset for testing
            create(:preset, :high_quality) unless Preset.find_by_name("high_quality")

            parser = described_class.new
            result = parser.send(:extract_parameters, "test --vibrant_colors --high_quality --width 800")

            # Should use the first preset found
            expect(result[:parsed_params][:preset]).to eq("vibrant_colors")
            expect(result[:parsed_params][:width]).to eq(800)
            expect(result[:clean_text]).to eq("test")
          end

          it "applies multiple direct preset names in order" do
            # Create additional presets for testing
            create(:preset, :realistic) unless Preset.find_by_name("realistic")
            create(:preset, :colorful) unless Preset.find_by_name("colorful")

            parser = described_class.new
            result = parser.parse("its a tables --realistic --colorful --steps 25", "flux")

            # Should apply both presets in order
            expect(result[:steps]).to eq(25) # User parameter overrides both presets
            expect(result[:model]).to eq("flux") # From realistic preset
            expect(result[:width]).to eq(800) # From colorful preset
            expect(result[:prompt]).to eq("its a tables photorealistic, detailed vibrant colors, saturated")
          end

          it "handles comma-separated preset names in --preset parameter" do
            # Create additional presets for testing
            create(:preset, :realistic) unless Preset.find_by_name("realistic")
            create(:preset, :colorful) unless Preset.find_by_name("colorful")

            parser = described_class.new
            result = parser.parse("its a tables --preset realistic,colorful --steps 25", "flux")

            # Should apply both presets in order
            expect(result[:steps]).to eq(25) # User parameter overrides both presets
            expect(result[:model]).to eq("flux") # From realistic preset
            expect(result[:width]).to eq(800) # From colorful preset
            expect(result[:prompt]).to eq("its a tables photorealistic, detailed vibrant colors, saturated")
          end

          it "handles mixed direct preset names and comma-separated presets" do
            # Create additional presets for testing
            create(:preset, :anime) unless Preset.find_by_name("anime")
            create(:preset, :photorealistic) unless Preset.find_by_name("photorealistic")
            create(:preset, :colorful) unless Preset.find_by_name("colorful")

            parser = described_class.new
            result = parser.parse("a beautiful scene --anime --preset photorealistic,colorful --steps 25", "flux")

            # Should apply all presets in order: photorealistic, colorful, anime
            expect(result[:steps]).to eq(25) # User parameter overrides all presets
            expect(result[:model]).to eq("qwen") # From anime preset (overrides photorealistic's flux)
            expect(result[:width]).to eq(800) # From colorful preset (overrides qwen defaults)
            expect(result[:prompt]).to eq("a beautiful scene photorealistic, detailed vibrant colors, saturated anime style, cel-shaded")
          end
        end
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
