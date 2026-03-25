class ListPresetsCommand < BaseCommand
  def execute
    debug("Handling list presets command")

    presets = Preset.order(:name).all

    if presets.empty?
      server.respond(message, "ℹ️ No presets available. Use `/create_preset` to create one.")
      return
    end

    response_parts = ["📋 **Available Presets:**\n"]

    presets.each do |preset|
      response_parts << "• **#{preset.name}**"
      response_parts << "  👤 Created by: #{preset.username || preset.user_id}"
      response_parts << "  📝 Prompt: #{preset.prompt.truncate(50)}"

      # Show some key parameters
      params = preset.parsed_parameters
      param_display = []
      param_display << "#{params[:steps]} steps" if params[:steps]
      param_display << params[:aspect_ratio] if params[:aspect_ratio]
      param_display << "#{params[:width]}x#{params[:height]}" if params[:width] && params[:height]
      param_display << params[:model] if params[:model]

      if param_display.any?
        response_parts << "  ⚙️ Parameters: #{param_display.join(", ")}"
      end

      # Show example image if available
      if preset.example_image
        response_parts << "  🖼️ Example: [here](#{preset.example_image})"
      end

      response_parts << "" # Empty line between presets
    end

    server.respond(message, response_parts.join("\n"))
  rescue => e
    debug("Error listing presets: #{e.message}\n#{e.backtrace.join("\n")}")
    server.respond(message, "❌ Error listing presets: #{e.message}")
  end
end
