class PromptParameterParser
  DEFAULT_CONFIGS = {
    flux: {
      width: 1024,
      height: 1024,
      steps: 2
    },
    qwen: {
      steps: 20,
      width: 1328,
      height: 1328,
      basesize: 1328,
      shift: 3.1
    }
  }

  def self.parse(*args)
    new.parse(*args)
  end

  def self.resolve_params(params)
    new.resolve_params(params)
  end

  def parse(full_prompt, model)
    # Check if this is a command (starts with /)
    if full_prompt.strip.start_with?("/")
      return CommandDispatcher.parse_command(full_prompt.strip)
    end

    result = extract_parameters(full_prompt)

    params = {
      model: model || "flux",
      seed: rand(1000000000),
      negative_prompt: ""
    }

    params[:model] = result.dig(:parsed_params, :model) if result[:parsed_params].has_key?(:model)
    default_params = DEFAULT_CONFIGS[params[:model].to_sym]
    params.merge!(default_params) if default_params.present?

    # Merge in the parsed parameters
    params.merge!(result[:parsed_params])
    params[:prompt] = result[:clean_text]
    resolve_params(params)
  end

  def resolve_params(params)
    params.tap do |params|
      resolve_aspect_ratio(params) if params.has_key?(:aspect_ratio)
    end
  end

  private

  # Shared method for extracting parameters from text
  def extract_parameters(text)
    params = {}
    clean_text = text.dup

    # Extract model first to determine basesize default
    if (match = text.match(/--model\s+(\w+)/))
      params[:model] = match[1].to_s
      clean_text.gsub!(/--model\s+(\w+)/, "")
    end

    if (match = text.match(/--basesize\s+(\d+)/))
      params[:basesize] = match[1].to_i
      clean_text.gsub!(/--basesize\s+\d+/, "")
    end

    # Extract aspect ratio first (this may override width/height)
    if (match = text.match(/--ar\s+([^\s-]+)/))
      params[:aspect_ratio] = match[1]
      clean_text.gsub!(/--ar\s+[^\s-]+/, "")
    end

    if (match = text.match(/--shift\s+(\d+.?\d*)/))
      params[:shift] = match[1].to_f
      clean_text.gsub!(/--shift\s+(\d+.?\d*)/, "")
    end

    # Extract width (this will override aspect ratio width if specified)
    if (match = text.match(/--width\s+(\d+)/))
      params[:width] = match[1].to_i
      clean_text.gsub!(/--width\s+\d+/, "")
    end

    # Extract height (this will override aspect ratio height if specified)
    if (match = text.match(/--height\s+(\d+)/))
      params[:height] = match[1].to_i
      clean_text.gsub!(/--height\s+\d+/, "")
    end

    # Extract steps
    if (match = text.match(/--steps\s+(\d+)/))
      params[:steps] = match[1].to_i
      clean_text.gsub!(/--steps\s+\d+/, "")
    end

    # Extract seed
    if (match = text.match(/--seed\s+(\d+)/))
      params[:seed] = match[1].to_i
      clean_text.gsub!(/--seed\s+\d+/, "")
    end

    # Extract negative prompt
    if (match = text.match(/--no\s+([^-]+)(?=\s*(?:--|$))/))
      params[:negative_prompt] = match[1].strip
      clean_text.gsub!(/--no\s+[^-]+(?=\s*(?:--|$))/, "")
    end

    # Extract private flag
    if text.match(/--private/)
      params[:private] = true
      clean_text.gsub!(/--private/, "")
    end

    # Clean up extra whitespace
    clean_text = clean_text.gsub(/\s+/, " ").strip

    {
      parsed_params: params,
      clean_text: clean_text
    }
  end

  def resolve_aspect_ratio(params)
    basesize = params[:basesize] || 1024
    width, height = aspect_ratio_to_dimensions(params[:aspect_ratio], basesize)
    params[:width] = width
    params[:height] = height
  end

  # Convert aspect ratio to width and height
  def aspect_ratio_to_dimensions(aspect_ratio, base_size = 1024)
    aspect_ratios = {
      # Standard ratios
      "1:1" => [1024, 1024],
      "4:3" => [1152, 864],
      "3:2" => [1216, 810],
      "16:10" => [1280, 800],
      "5:4" => [1024, 819],
      "3:4" => [864, 1152],
      "2:3" => [810, 1216],
      "10:16" => [800, 1280],
      "4:5" => [819, 1024],

      # Widescreen ratios
      "16:9" => [1344, 768],
      "21:9" => [1536, 658],
      "32:9" => [1792, 512],

      # Portrait versions
      "9:16" => [768, 1344],
      "9:21" => [658, 1536],
      "9:32" => [512, 1792],

      # Cinema ratios
      "2.35:1" => [1472, 626],
      "2.4:1" => [1536, 640],
      "1:2.35" => [626, 1472],
      "1:2.4" => [640, 1536]
    }

    if aspect_ratios.key?(aspect_ratio) && base_size == 1024
      aspect_ratios[aspect_ratio]
    elsif (match = aspect_ratio.match(/^(\d+(?:\.\d+)?):(\d+(?:\.\d+)?)$/))
      # Try to parse custom ratios like "16:9"
      w_ratio = match[1].to_f
      h_ratio = match[2].to_f

      # Calculate dimensions maintaining aspect ratio with base_size as reference
      if w_ratio >= h_ratio
        width = base_size
        height = (base_size * h_ratio / w_ratio).round
      else
        height = base_size
        width = (base_size * w_ratio / h_ratio).round
      end

      # Make sure dimensions are multiples of 8 (common requirement for AI models)
      width = (width / 8).round * 8
      height = (height / 8).round * 8

      [width, height]
    else
      [1024, 1024] # Default fallback
    end
  end
end
