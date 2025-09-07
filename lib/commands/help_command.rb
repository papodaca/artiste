require_relative "base_command"

class HelpCommand < BaseCommand
  def execute
    debug_log("Handling help command")
    help_text = parsed_result[:help_text]
    mattermost.respond(message, help_text)
  end
end
