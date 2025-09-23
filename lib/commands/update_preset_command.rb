class UpdatePresetCommand < BaseCommand
  def self.parse(params_string)
    # Parse the command: /update_preset <name> <prompt>
    if (match = %r{^(\w+)\s+(.+)$}.match(params_string))
      {
        name: match[1],
        prompt: match[2]
      }
    else
      {error: "Invalid format. Use: /update_preset <name> <prompt>"}
    end
  end

  def execute
    debug_log("Handling update preset command")

    if parsed_result[:error]
      server.respond(message, "❌ #{parsed_result[:error]}")
      return
    end

    preset_name = parsed_result[:name]
    prompt_text = parsed_result[:prompt]

    # Find existing preset
    existing_preset = Preset.find_by_name(preset_name)
    unless existing_preset
      server.respond(message, "❌ Preset '#{preset_name}' not found. Use `/create_preset` to create it first.")
      return
    end

    unless existing_preset.user_id == user_settings.user_id
      server.respond(message, "❌ You can only update presets you created. This preset was created by #{existing_preset.username || existing_preset.user_id}.")
      return
    end

    # Parse the prompt using PromptParameterParser
    parser = PromptParameterParser.new
    parsing_result = parser.parse(prompt_text, nil, for_preset: true)

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

    # Update the preset
    existing_preset.prompt = final_params[:prompt]
    existing_preset.parameters = parameters_to_save.to_json
    existing_preset.example_image = example_image if example_image

    if existing_preset.save
      debug_log("Preset updated successfully: #{preset_name}")
      response = "✅ Preset '#{preset_name}' updated successfully!\n" \
                "📝 New prompt: #{final_params[:prompt]}\n" \
                "⚙️ New parameters: #{parameters_to_save.inspect}"

      if example_image
        response += "\n🖼️ New example image: [#{example_image}]()"
      end

      server.respond(message, response)
    else
      debug_log("Failed to update preset: #{existing_preset.errors.full_messages.join(", ")}")
      server.respond(message, "❌ Failed to update preset '#{preset_name}'. Please try again.")
    end
  rescue => e
    debug_log("Error updating preset: #{e.message}\n#{e.backtrace.join("\n")}")
    server.respond(message, "❌ Error updating preset: #{e.message}")
  end
end
