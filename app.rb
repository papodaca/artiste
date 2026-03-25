#!/usr/bin/env ruby
require "optparse"
require_relative "config/environment"

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"

  opts.on("-g", "--debug", "Enable debug mode") do |v|
    options[:debug] = v
  end

  opts.on("-w", "--web", "Enable the web server") do |v|
    options[:web] = v
  end

  opts.on("-d", "--dev", "Enable development mode (debug + web server + bun dev)") do |v|
    options[:dev] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

options[:web] = true if options[:dev]

if options[:dev]
  ENV["RACK_ENV"] = "development"

  Bundler.require(:default, :development)

  bun_dev_pid = Process.spawn("bun dev")
  Logging.info "Started bun dev with PID #{bun_dev_pid}"
  at_exit do
    Logging.info "Terminating bun dev (PID #{bun_dev_pid})"
    Process.kill("TERM", bun_dev_pid)
    Process.wait(bun_dev_pid)
  end

  restart = false
  root = File.dirname(__FILE__)
  listener = Listen.to(File.join(root, "lib"), only: /\.rb$/) do |modified, added, removed|
    changed = (modified + added + removed).map { |f| f.sub("#{root}/", "") }
    Logging.info "#{changed.join(", ")} changed — reloading..."
    restart = true
    EM.next_tick { EM.stop } if EM.reactor_running?
  end
  listener.start

  loop do
    LOADER.reload if restart
    restart = false
    Artiste.new(options).start
    break unless restart
  end
else
  Artiste.new(options).start
end
