class UnknownCommand < BaseCommand
  def execute
    debug("Handling unknown command")
    error_msg = parsed_result[:error] || "Unknown command"
    debug("Unknown command error: #{error_msg}")
    server.respond(message, "❌ #{error_msg}")
  end
end
