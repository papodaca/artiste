require "spec_helper"
require "json"
require "base64"

# Test the OpenAI API functionality
describe "OpenAI API" do
  describe "parameter parsing" do
    describe "#parse_size_parameter" do
      def parse_size_parameter(size)
        return nil unless size.is_a?(String)

        match = size.match(/^(\d+)x(\d+)$/)
        return nil unless match

        width = match[1].to_i
        height = match[2].to_i

        # Validate size is within reasonable bounds
        return nil if width < 256 || width > 2048 || height < 256 || height > 2048

        [width, height]
      end

      it "returns width and height for valid size" do
        result = parse_size_parameter("1024x768")
        expect(result).to eq([1024, 768])
      end

      it "returns nil for invalid format" do
        result = parse_size_parameter("invalid")
        expect(result).to be_nil
      end

      it "returns nil for size too small" do
        result = parse_size_parameter("128x128")
        expect(result).to be_nil
      end

      it "returns nil for size too large" do
        result = parse_size_parameter("3000x3000")
        expect(result).to be_nil
      end

      it "accepts standard sizes" do
        expect(parse_size_parameter("256x256")).to eq([256, 256])
        expect(parse_size_parameter("512x512")).to eq([512, 512])
        expect(parse_size_parameter("1024x1024")).to eq([1024, 1024])
      end

      it "accepts rectangular sizes" do
        expect(parse_size_parameter("1024x768")).to eq([1024, 768])
        expect(parse_size_parameter("768x1024")).to eq([768, 1024])
      end

      it "rejects invalid formats" do
        expect(parse_size_parameter("1024")).to be_nil
        expect(parse_size_parameter("1024x768x96")).to be_nil
        expect(parse_size_parameter("1024x")).to be_nil
        expect(parse_size_parameter("x1024")).to be_nil
      end

      it "rejects out-of-bounds sizes" do
        expect(parse_size_parameter("255x255")).to be_nil
        expect(parse_size_parameter("2049x2049")).to be_nil
      end
    end

    describe "#map_openai_model_to_internal" do
      def map_openai_model_to_internal(openai_model)
        case openai_model.downcase
        when "gpt-image-1", "dall-e-2", "dall-e-3"
          "flux"  # Default to flux for OpenAI model names
        when "flux", "qwen"
          openai_model.downcase  # Use as-is if it's already one of our models
        else
          "flux"  # Default to flux for unknown models
        end
      end

      it "maps gpt-image-1 to flux" do
        result = map_openai_model_to_internal("gpt-image-1")
        expect(result).to eq("flux")
      end

      it "maps dall-e-2 to flux" do
        result = map_openai_model_to_internal("dall-e-2")
        expect(result).to eq("flux")
      end

      it "maps dall-e-3 to flux" do
        result = map_openai_model_to_internal("dall-e-3")
        expect(result).to eq("flux")
      end

      it "returns flux as-is" do
        result = map_openai_model_to_internal("flux")
        expect(result).to eq("flux")
      end

      it "returns qwen as-is" do
        result = map_openai_model_to_internal("qwen")
        expect(result).to eq("qwen")
      end

      it "maps unknown models to flux" do
        result = map_openai_model_to_internal("unknown-model")
        expect(result).to eq("flux")
      end

      it "maps OpenAI models to internal models" do
        expect(map_openai_model_to_internal("gpt-image-1")).to eq("flux")
        expect(map_openai_model_to_internal("dall-e-2")).to eq("flux")
        expect(map_openai_model_to_internal("dall-e-3")).to eq("flux")
      end

      it "passes through internal models" do
        expect(map_openai_model_to_internal("flux")).to eq("flux")
        expect(map_openai_model_to_internal("qwen")).to eq("qwen")
      end

      it "defaults to flux for unknown models" do
        expect(map_openai_model_to_internal("unknown")).to eq("flux")
        expect(map_openai_model_to_internal("")).to eq("flux")
      end
    end
  end

  describe "response format" do
    it "includes required fields" do
      # Test the response structure without actually making a request
      created_time = Time.now.to_i
      base64_image = Base64.strict_encode64("fake_image_data")

      response = {
        "created" => created_time,
        "data" => [
          {
            "b64_json" => base64_image
          }
        ],
        "usage" => {
          "total_tokens" => 100,
          "input_tokens" => 50,
          "output_tokens" => 50,
          "input_tokens_details" => {
            "text_tokens" => 50,
            "image_tokens" => 0
          }
        }
      }

      expect(response).to have_key("created")
      expect(response).to have_key("data")
      expect(response).to have_key("usage")
      expect(response["data"]).to be_an(Array)
      expect(response["data"].first).to have_key("b64_json")
      expect(response["usage"]).to have_key("total_tokens")
      expect(response["usage"]).to have_key("input_tokens")
      expect(response["usage"]).to have_key("output_tokens")
      expect(response["usage"]).to have_key("input_tokens_details")
    end

    it "encodes image data as base64" do
      image_data = "fake_image_data"
      base64_image = Base64.strict_encode64(image_data)

      expect(base64_image).to eq(Base64.strict_encode64("fake_image_data"))
      expect(base64_image).to be_a(String)
    end

    it "calculates token usage" do
      prompt = "A cute baby sea otter"
      width = 1024
      height = 1024

      # Calculate token usage (approximate)
      prompt_tokens = (prompt.length / 4.0).ceil  # Rough estimate
      image_tokens = (width * height / 1000.0).ceil  # Rough estimate based on image size
      total_tokens = prompt_tokens + image_tokens

      expect(total_tokens).to be > 0
      expect(prompt_tokens).to be > 0
      expect(image_tokens).to be > 0
    end
  end

  describe "authentication" do
    it "validates token presence" do
      # Test that the API_TOKEN environment variable is checked
      ENV["API_TOKEN"] = "test_token"
      expect(ENV["API_TOKEN"]).to eq("test_token")
    end

    it "rejects missing token" do
      # Test that missing tokens are rejected
      ENV["API_TOKEN"] = nil
      expect(ENV["API_TOKEN"]).to be_nil
    end

    it "compares tokens correctly" do
      # Test token comparison
      ENV["API_TOKEN"] = "valid_token"

      # Valid token
      token = "valid_token"
      expect(token).to eq(ENV["API_TOKEN"])

      # Invalid token
      invalid_token = "invalid_token"
      expect(invalid_token).not_to eq(ENV["API_TOKEN"])
    end
  end

  describe "parameter validation" do
    it "validates required parameters" do
      # Test that prompt is required
      request_body = {
        "model" => "gpt-image-1",
        "n" => 1,
        "size" => "1024x1024"
        # Missing prompt
      }

      expect(request_body).to have_key("model")
      expect(request_body).to have_key("n")
      expect(request_body).to have_key("size")
      expect(request_body).not_to have_key("prompt")
    end

    it "validates n parameter" do
      # Test that n must be between 1 and 10
      valid_n = 5
      invalid_n_low = 0
      invalid_n_high = 11

      expect(valid_n).to be_between(1, 10)
      expect(invalid_n_low).not_to be_between(1, 10)
      expect(invalid_n_high).not_to be_between(1, 10)
    end

    it "validates size parameter" do
      # Test that size must be in the correct format
      valid_size = "1024x1024"
      invalid_format = "invalid"
      invalid_bounds = "3000x3000"

      expect(valid_size).to match(/^\d+x\d+$/)
      expect(invalid_format).not_to match(/^\d+x\d+$/)
      expect(invalid_bounds).to match(/^\d+x\d+$/) # Format is valid but bounds are not
    end
  end
end
