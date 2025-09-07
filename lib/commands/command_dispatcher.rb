require_relative "base_command"
require_relative "set_settings_command"
require_relative "get_settings_command"
require_relative "get_details_command"
require_relative "help_command"
require_relative "unknown_command"

COMMANDS = {
  set_settings: SetSettingsCommand,
  get_settings: GetSettingsCommand,
  get_details: GetDetailsCommand,
  help: HelpCommand,
  unknown_command: UnknownCommand
}.freeze

class CommandDispatcher
  def self.execute(mattermost, message, parsed_result, user_settings, debug_log_enabled)
    command_type = parsed_result[:type]
    command_class = COMMANDS[command_type]
    if command_class.nil?
      command_class = UnknownCommand
      parsed_result[:type] = :unknown_command
      parsed_result[:error] = "Unknown command type: #{command_type}"
    end

    command = command_class.new(mattermost, message, parsed_result, user_settings, debug_log_enabled)
    command.execute
  end
end
