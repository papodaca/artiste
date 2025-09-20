class CreatePresetCommand < BaseCommand
  def self.parse(params_string)
    # Parse the command: /create-preset <name> <prompt>
    if (match = %r{^(\w+)\s+(.+)$}.match(params_string))
      {
        name: match[1],
        prompt: match[2]
      }
    else
      {error: "Invalid format. Use: /create-preset <name> <prompt>"}
    end
  end

  def execute
    debug_log("Handling create preset command")

    if parsed_result[:error]
      server.respond(message, "❌ #{parsed_result[:error]}")
      return
    end

    preset_name = parsed_result[:name]
    prompt_text = parsed_result[:prompt]

    # Check if preset name conflicts with parameter names
    if invalid_preset_name?(preset_name)
      server.respond(message, "❌ Preset name '#{preset_name}' conflicts with a parameter name. Choose a different name.")
      return
    end

    # Check if preset with this name already exists (global check, not per user)
    existing_preset = Preset.where(name: preset_name).first
    if existing_preset
      server.respond(message, "❌ A preset named '#{preset_name}' already exists. Use a different name.")
      return
    end

    # Parse the prompt using PromptParameterParser
    parser = PromptParameterParser.new
    parsing_result = parser.parse(prompt_text, nil, for_preset: true) # model will be auto-detected from prompt

    # Only save parameters that were explicitly provided by the user
    final_params = parsing_result[:final_params]
    explicitly_provided_params = parsing_result[:explicitly_provided_params]

    # Filter parameters to only include those explicitly provided
    parameters_to_save = {}
    explicitly_provided_params.each do |param_name|
      parameters_to_save[param_name] = final_params[param_name] if final_params.has_key?(param_name)
    end

    # Extract image parameter if provided (remove from parameters_to_save since it's stored separately)
    example_image = parameters_to_save.delete(:image)

    # Create the preset
    preset = Preset.new(
      name: preset_name,
      user_id: user_settings.user_id,
      username: user_settings.username,
      prompt: final_params[:prompt],
      parameters: parameters_to_save.to_json,
      example_image: example_image
    )

    if preset.save
      debug_log("Preset saved successfully: #{preset_name}")
      response = "✅ Preset '#{preset_name}' created successfully!\n" \
                "📝 Prompt: #{final_params[:prompt]}\n" \
                "⚙️ Parameters: #{parameters_to_save.inspect}"
      
      if example_image
        response += "\n🖼️ Example image: ![example](#{example_image})"
      end
      
      server.respond(message, response)
    else
      debug_log("Failed to save preset: #{preset.errors.full_messages.join(", ")}")
      server.respond(message, "❌ Failed to create preset '#{preset_name}'. Please try again.")
    end
  rescue => e
    debug_log("Error creating preset: #{e.message}\n#{e.backtrace.join("\n")}")
    server.respond(message, "❌ Error creating preset: #{e.message}")
  end

  private

  def invalid_preset_name?(name)
    # List of parameter names that cannot be used as preset names
    # These are the keys from PromptParameterParser::PARAMS
    parameter_names = [
      "model", "basesize", "aspect_ratio", "shift", "width", "height",
      "steps", "seed", "negative_prompt", "preset", "private", "no", "ar"
    ]

    # Also check for shorthand parameter names
    shorthand_names = ["m", "b", "a", "S", "w", "h", "s", "n", "P", "p"]

    parameter_names.include?(name.downcase) || shorthand_names.include?(name.downcase)
  end
end
