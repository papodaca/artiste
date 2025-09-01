class BaseCommand
  attr_reader :mattermost, :message, :parsed_result, :user_settings

  def initialize(mattermost, message, parsed_result = nil, user_settings = nil)
    @mattermost = mattermost
    @message = message
    @parsed_result = parsed_result
    @user_settings = user_settings
  end

  def execute
    raise NotImplementedError, "Subclasses must implement the execute method"
  end

  private

  def debug_log(message)
    puts "[DEBUG] #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} - #{message}" if $DEBUG_MODE
  end

  def print_settings(out, settings)
    out << "```"
    settings.each do |key, value|
      out << "#{key.to_s.titleize}: #{value}"
    end
    out << "```"
  end
end
