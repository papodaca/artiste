COMMANDS = {
  set_settings: {match: %r{^/set_settings\s+(.+)}, class: SetSettingsCommand},
  get_settings: {match: "/get_settings", class: GetSettingsCommand},
  details: {match: %r{^/details\s+(.+)}, class: GetDetailsCommand},
  help: {match: "/help", class: HelpCommand},
  text: {match: %r{^/text\s+(.+)}, class: TextCommand},
  video: {match: %r{^/video\s+(.+)}, class: VideoCommand},
  edit: {match: %r{^/edit\s+(.+)}, class: EditCommand},
  generate: {match: %r{^/generate\s+(.+)}, class: GenerateCommand},
  create_preset: {match: %r{^/create_preset\s+(.+)}, class: CreatePresetCommand},
  list_presets: {match: %r{^/list_presets(?:\s|$)}, class: ListPresetsCommand},
  update_preset: {match: %r{^/update_preset\s+(.+)}, class: UpdatePresetCommand},
  delete_preset: {match: %r{^/delete_preset\s+(.+)}, class: DeletePresetCommand},
  show_preset: {match: %r{^/show_preset\s+(.+)}, class: ShowPresetCommand},
  unknown_command: {class: UnknownCommand}
}.freeze

class CommandDispatcher
  def self.execute(*args)
    command_type = args.dig(2, :type)

    # Handle unknown command types
    if !COMMANDS.key?(command_type) || COMMANDS[command_type].nil?
      # Transform the parsed_result to have the correct type and error message
      parsed_result = args[2] || {}
      error_msg = "Unknown command type: #{command_type || ""}"
      # Override the type and error in the parsed_result
      modified_parsed_result = parsed_result.merge({type: :unknown_command, error: error_msg})
      # Create new args with modified parsed_result
      modified_args = args.dup
      modified_args[2] = modified_parsed_result
      command_class = UnknownCommand
      command_class.new(*modified_args).execute
    else
      command_class = COMMANDS.dig(command_type, :class)
      command_class.new(*args).execute
    end
  end

  def self.parse_command(command_string)
    COMMANDS.each do |type, command|
      next unless command.has_key?(:match)
      if command[:match].is_a?(String) && command_string.strip == command[:match]
        return {type:}
      elsif command[:match].is_a?(Regexp) && (match = command[:match].match(command_string))
        params = command[:class].parse(*match.to_a[1..]) if command[:class].respond_to?(:parse)
        return {type:}.merge(params || {})
      end
    end
    {type: :unknown_command, error: "Unknown command: #{command_string}"}
  end
end
