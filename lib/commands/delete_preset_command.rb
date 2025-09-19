class DeletePresetCommand < BaseCommand
  def self.parse(params_string)
    # Parse the command: /delete_preset <name>
    if (match = %r{^(\w+)$}.match(params_string.strip))
      {
        name: match[1]
      }
    else
      {error: "Invalid format. Use: /delete_preset <name>"}
    end
  end

  def execute
    debug_log("Handling delete preset command")

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

    # Check if the current user is the creator
    unless existing_preset.user_id == user_settings.user_id
      server.respond(message, "❌ You can only delete presets you created. This preset was created by #{existing_preset.username || existing_preset.user_id}.")
      return
    end

    # Delete the preset
    if existing_preset.destroy
      debug_log("Preset deleted successfully: #{preset_name}")
      server.respond(message, "🗑️ Preset '#{preset_name}' deleted successfully!")
    else
      debug_log("Failed to delete preset: #{existing_preset.errors.full_messages.join(", ")}")
      server.respond(message, "❌ Failed to delete preset '#{preset_name}'. Please try again.")
    end
  rescue => e
    debug_log("Error deleting preset: #{e.message}\n#{e.backtrace.join("\n")}")
    server.respond(message, "❌ Error deleting preset: #{e.message}")
  end
end
