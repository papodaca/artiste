class SetSettingsCommand < BaseCommand
  def self.parse(params_string)
    # Create a temporary parser instance to use its extract_parameters method
    parser = PromptParameterParser.new
    result = parser.send(:extract_parameters, params_string)
    delete_keys = params_string.scan(/--delete\s+(\w+)/).map { |s| s[0].to_sym }

    {
      settings: result[:parsed_params],
      delete_keys: delete_keys
    }
  end

  def execute
    debug_log("Handling set settings command")
    settings = parsed_result[:settings]
    delete_keys = parsed_result[:delete_keys] || []
    debug_log("Settings to update: #{settings.inspect}")
    debug_log("Keys to delete: #{delete_keys.inspect}")

    if settings.empty? && delete_keys.empty?
      debug_log("No settings or delete operations provided in command")
      server.respond(message, "❌ No settings or delete operations provided. Use `/help` to see available options.")
      return
    end

    # Handle deletions first
    deleted_keys = []

    delete_keys.each do |key|
      debug_log("Deleting setting: #{key}")
      synonym_key = synonym(key)
      sym = synonym_key.to_sym if synonym_key
      if sym && user_settings.delete_param(sym)
        deleted_keys << sym.to_s.titleize
      end
    end

    # Update user settings
    #
    if settings.has_key?(:aspect_ratio)
      debug_log("Aspect ratio detected, removing width/height settings")
      settings.delete(:width)
      settings.delete(:height)
    end
    settings.each do |key, value|
      debug_log("Setting #{key} = #{value}")
      user_settings.set_param(key.to_sym, value)
    end

    user_settings.save
    debug_log("User settings saved successfully")

    # Build response message
    response_parts = []

    if deleted_keys.any?
      response_parts << "🗑️ **Deleted settings:** #{deleted_keys.join(", ")}"
    end

    if settings.any?
      settings_text = []
      print_settings(settings_text, user_settings.parsed_prompt_params)
      response_parts << "✅ **Updated settings:**\n#{settings_text.join("\n")}"
    end

    if response_parts.empty?
      response_parts << "ℹ️ No changes made to settings."
    end

    response = response_parts.join("\n\n")
    server.respond(message, response)
  end

  private

  SYNONYMS = {
    "aspect_ratio" => ["ar", "aspectratio", "aspect_ratio"],
    "width" => ["w", "width"],
    "height" => ["h", "height"],
    "steps" => ["s", "steps"],
    "model" => ["m", "model"],
    "shift" => ["sh", "shift"],
    "basesize" => ["bs", "basesize"]
  }.freeze

  def synonym(name)
    SYNONYMS.each do |k, v|
      return k if v.include?(name.to_s)
    end
    nil
  end
end
