class ShowPresetCommand < BaseCommand
  def self.parse(params_string)
    # Parse the command: /show_preset <name>
    if (match = %r{^(\w+)$}.match(params_string.strip))
      {
        name: match[1]
      }
    else
      {error: "Invalid format. Use: /show_preset <name>"}
    end
  end

  def execute
    debug_log("Handling show preset command")

    if parsed_result[:error]
      server.respond(message, "❌ #{parsed_result[:error]}")
      return
    end

    preset_name = parsed_result[:name]

    # Find existing preset
    existing_preset = Preset.find_by_name(preset_name)
    unless existing_preset
      server.respond(message, "❌ Preset '#{preset_name}' not found.")
      return
    end

    # Build detailed response
    params = existing_preset.parsed_parameters

    response_parts = [
      "📋 **Preset Details: #{preset_name}**",
      "",
      "👤 **Created by:** #{existing_preset.username || existing_preset.user_id}",
      "🕒 **Created at:** #{existing_preset.created_at.strftime("%Y-%m-%d %H:%M")}",
      "📝 **Prompt:** #{existing_preset.prompt}",
      "",
      "⚙️ **Parameters:**"
    ]



    # Add all parameters in a formatted way
    if params.any?
      params.each do |key, value|
        response_parts << "  • #{key.to_s.titleize}: #{value}"
      end
    else
      response_parts << "  • No additional parameters"
    end

    if existing_preset.example_image
      response_parts << "  🖼️ Example:\n![example](#{existing_preset.example_image})"
    end

    server.respond(message, response_parts.join("\n"))
  rescue => e
    debug_log("Error showing preset: #{e.message}\n#{e.backtrace.join("\n")}")
    server.respond(message, "❌ Error showing preset: #{e.message}")
  end
end
