class BaseCommand
  include Logging

  attr_reader :server, :message, :parsed_result, :user_settings

  def initialize(server, message, parsed_result = nil, user_settings = nil)
    @server = server
    @message = message
    @parsed_result = parsed_result
    @user_settings = user_settings
  end

  def execute
    raise NotImplementedError, "Subclasses must implement the execute method"
  end

  private

  def print_settings(out, settings)
    out << "```"
    settings.each do |key, value|
      out << "#{key.to_s.titleize}: #{value}"
    end
    out << "```"
  end
end
