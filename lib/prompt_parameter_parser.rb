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
    preset: {match: %r{(?:--preset(?:=|\s+)|-P\s+)([\w,]+)}, clean: %r{(?:--preset(?:=|\s+)|-P\s+)[\w,]+}, parse: :to_s},
    private: {match: %r{(--private|-p)}, clean: %r{(--private|-p)}, parse: :present?},
    image: {match: %r{(?:--image(?:=|\s+)|-i\s+)(https?://[^\s]+)}, clean: %r{(?:--image(?:=|\s+)|-i\s+)https?://[^\s]+}, parse: :to_s}
  }

  def self.parse(*args)
    new.parse(*args)
  end

  def self.resolve_params(params)
    new.resolve_params(params)
  end

  def parse(full_prompt, model, for_preset: false)
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

    # Track which parameters were explicitly provided
    explicitly_provided_params = result[:parsed_params].keys.dup

    # Handle both old single preset and new multiple presets format
    if explicitly_provided_params.include?(:presets)
      explicitly_provided_params.delete(:presets)
      explicitly_provided_params << :preset
    end

    # Apply preset parameters if specified (support multiple presets)
    presets_to_apply = []

    # Handle both old single preset format and new multiple presets format
    if result[:parsed_params].has_key?(:preset)
      # Handle comma-separated preset values
      preset_value = result[:parsed_params][:preset]
      if preset_value.include?(",")
        presets_to_apply.concat(preset_value.split(",").map(&:strip))
      else
        presets_to_apply << preset_value
      end
    end

    if result[:parsed_params].has_key?(:presets)
      presets_to_apply.concat(result[:parsed_params][:presets])
    end

    # Also handle direct preset names that were found but not stored in :preset
    # (for backward compatibility with existing tests)
    if result[:parsed_params].has_key?(:preset)
      # Look for additional direct preset names in the original text
      full_prompt.scan(/--(\w+)/) do |match|
        preset_name = match[0]
        # Check if this is a valid preset name (not a regular parameter)
        unless PARAMS.key?(preset_name.to_sym) || PARAMS.any? { |_, v| v[:match].match?("--#{preset_name}") }
          preset = Preset.find_by_name(preset_name)
          if preset && preset_name != result[:parsed_params][:preset]
            presets_to_apply << preset_name
          end
        end
      end
    end

    # Remove duplicates to prevent processing the same preset multiple times
    presets_to_apply.uniq!

    # Apply presets in order (first to last)
    presets_to_apply.each do |preset_name|
      preset = Preset.find_by_name(preset_name)

      if preset
        preset_params = preset.parsed_parameters
        # Merge preset parameters, but don't override existing ones
        preset_params.each do |key, value|
          params[key] = value unless result[:parsed_params].has_key?(key)
          # Mark that these parameters came from a preset so they won't be overridden by defaults
          params[:"_preset_#{key}"] = true
        end

        # Append preset prompt to the current prompt
        if preset.prompt && !preset.prompt.empty?
          result[:clean_text] = "#{result[:clean_text]} #{preset.prompt}".strip
        end
      end
    end

    params[:model] = result.dig(:parsed_params, :model) if result[:parsed_params].has_key?(:model)
    default_params = DEFAULT_CONFIGS[params[:model].to_sym]
    if default_params && !default_params.empty?
      # Apply defaults only for parameters that weren't set by presets
      default_params.each do |key, value|
        params[key] = value unless params.has_key?(:"_preset_#{key}")
      end
    end

    # Merge in the parsed parameters (preset params already handled above)
    non_preset_params = result[:parsed_params].except(:preset, :presets)
    params.merge!(non_preset_params)
    params[:prompt] = result[:clean_text]
    final_params = resolve_params(params)

    # For preset creation, we need to include derived parameters that should be saved
    # 1. If aspect_ratio is provided, include width and height
    if explicitly_provided_params.include?(:aspect_ratio)
      explicitly_provided_params << :width << :height
    end

    # 2. If basesize is provided and model-specific default would set width/height, include them
    if explicitly_provided_params.include?(:basesize) && final_params[:width] == final_params[:height]
      # Only include width/height if they're equal (square aspect ratio from basesize)
      explicitly_provided_params << :width << :height
    end

    # 3. Clean up any duplicates
    explicitly_provided_params.uniq!

    if for_preset
      # Return both final params and info about which were explicitly provided
      {
        final_params: final_params,
        explicitly_provided_params: explicitly_provided_params
      }
    else
      # Return just the final params for backward compatibility
      final_params
    end
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

    # Extract direct preset names first (--<preset_name> syntax)
    clean_text = extract_direct_preset_names(clean_text, params)

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

  # Extract direct preset names from text (--<preset_name> syntax)
  def extract_direct_preset_names(text, params)
    clean_text = text.dup
    # Look for --<word> patterns that match existing preset names
    text.scan(/--(\w+)/) do |match|
      preset_name = match[0]
      # Check if this is a valid preset name (not a regular parameter)
      unless PARAMS.key?(preset_name.to_sym) || PARAMS.any? { |_, v| v[:match].match?("--#{preset_name}") }
        preset = Preset.find_by_name(preset_name)
        if preset
          # For backward compatibility with existing tests, only store the first preset in :preset
          # and ignore subsequent ones (but still apply them for parameter merging)
          unless params[:preset]
            params[:preset] = preset_name
          end
          # Remove the direct preset reference from text
          clean_text.gsub!("--#{preset_name}", "")
        end
      end
    end
    clean_text
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
