class BaseCommand
  attr_reader :mattermost, :message, :parsed_result, :user_settings, :debug_log_enabled

  def initialize(mattermost, message, parsed_result = nil, user_settings = nil, debug_log_enabled = false)
    @mattermost = mattermost
    @message = message
    @parsed_result = parsed_result
    @user_settings = user_settings
    @debug_log_enabled = debug_log_enabled
  end

  def execute
    raise NotImplementedError, "Subclasses must implement the execute method"
  end

  private

  def debug_log(message)
    return unless debug_log_enabled
    puts "[DEBUG] #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} - #{message}"
  end

  def print_settings(out, settings)
    out << "```"
    settings.each do |key, value|
      out << "#{key.to_s.titleize}: #{value}"
    end
    out << "```"
  end
end
