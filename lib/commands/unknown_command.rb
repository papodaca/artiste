class UnknownCommand < BaseCommand
  def execute
    debug_log("Handling unknown command")
    error_msg = parsed_result[:error] || "Unknown command"
    debug_log("Unknown command error: #{error_msg}")
    server.respond(message, "❌ #{error_msg}")
  end
end
