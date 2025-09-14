class GetSettingsCommand < BaseCommand
  def execute
    debug_log("Handling get settings command")

    if user_settings.nil? || user_settings.parsed_prompt_params.empty?
      server.respond(message, "ℹ️ No settings set.")
    else
      settings_text = []
      print_settings(settings_text, user_settings.parsed_prompt_params)
      debug_log("Retrieved user settings: #{user_settings.parsed_prompt_params.inspect}")

      server.respond(message, "⚙️ **Current Settings:**\n#{settings_text.join("\n")}")
    end
  end
end
