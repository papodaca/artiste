require "logger"

module Logging
  def self.logger
    @logger ||= Logger.new($stdout).tap do |log|
      log.level = Logger::INFO
      log.formatter = proc do |severity, datetime, _progname, msg|
        "[#{severity.ljust(5)}] #{datetime.strftime("%Y-%m-%d %H:%M:%S")} #{msg}\n"
      end
    end
  end

  def self.level=(level)
    logger.level = level
  end

  %i[debug info warn error fatal].each do |level|
    define_method(level) { |msg| Logging.logger.public_send(level, msg) }
    define_method(:"#{level}?") { Logging.logger.public_send(:"#{level}?") }
    define_singleton_method(level) { |msg| Logging.logger.public_send(level, msg) }
    define_singleton_method(:"#{level}?") { Logging.logger.public_send(:"#{level}?") }
  end
end
