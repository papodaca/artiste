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

  PARAMS = {
    model: {match: %r{(?:--model(?:=|\s+)|-m\s+)(\w+)}, clean: %r{(?:--model(?:=|\s+)|-m\s+)\w+}, parse: :to_s},
    basesize: {match: %r{(?:--basesize(?:=|\s+)|-b\s+)(\d+)}, clean: %r{(?:--basesize(?:=|\s+)|-b\s+)\d+}, parse: :to_i},
    aspect_ratio: {match: %r{(?:--ar(?:=|\s+)|-a\s+)([^\s-]+)}, clean: %r{(?:--ar(?:=|\s+)|-a\s+)[^\s-]+}, parse: :to_s},
    shift: {match: %r{(?:--shift(?:=|\s+)|-S\s+)(\d+.?\d*)}, clean: %r{(?:--shift(?:=|\s+)|-S\s+)\d+.?\d*}, parse: :to_f},
    width: {match: %r{(?:--width(?:=|\s+)|-w\s+)(\d+)}, clean: %r{(?:--width(?:=|\s+)|-w\s+)\d+}, parse: :to_i},
    height: {match: %r{(?:--height(?:=|\s+)|-h\s+)(\d+)}, clean: %r{(?:--height(?:=|\s+)|-h\s+)(\d+)}, parse: :to_i},
    steps: {match: %r{(?:--steps(?:=|\s+)|-s\s+)(\d+)}, clean: %r{(?:--steps(?:=|\s+)|-s\s+)\d+}, parse: :to_i},
    seed: {match: %r{--seed(?:=|\s+)(\d+)}, clean: %r{--seed(?:=|\s+)\d+}, parse: :to_i},
    negative_prompt: {match: %r{(?:--no(?:=|\s+)|-n\s+)([^-\s](?:[^-]*(?:\s+[^-]+)*))(?=\s*(?:--|$|\s-[a-zA-Z]))}, clean: %r{(?:--no(?:=|\s+)|-n\s+)[^-\s](?:[^-]*(?:\s+[^-]+)*)(?=\s*(?:--|$|\s-[a-zA-Z]))}, parse: :strip},
    private: {match: %r{(--private|-p)}, clean: %r{(--private|-p)}, parse: :present?}
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
    params.merge!(default_params) if default_params && !default_params.empty?

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

    PARAMS.each do |k, v|
      if (match = v[:match].match(clean_text))
        params[k] = match[1].send(v[:parse])
        clean_text.gsub!(v[:clean], "")
      end
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
