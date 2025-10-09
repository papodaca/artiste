#!/usr/bin/env ruby
require "optparse"
require "fileutils"
require_relative "config/environment"

# Parse command line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"

  opts.on("-g", "--debug", "Enable debug mode") do |v|
    options[:debug] = v
  end

  opts.on("-w", "--web", "Enable the web server") do |v|
    options[:web] = v
  end

  opts.on("-d", "--dev", "Enable development mode (debug + web server + yarn dev)") do |v|
    options[:dev] = v
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Set debug flag globally
# Enable debug mode if --debug or --dev flag is used
DEBUG_MODE = (options[:debug] || options[:dev] || false).freeze

# Enable web server if --web or --dev flag is used
options[:web] = true if options[:dev]

def debug_log(message)
  puts "[DEBUG] #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} - #{message}" if DEBUG_MODE
end

# Spawn yarn dev process if --dev flag is used
yarn_dev_pid = nil
if options[:dev]
  frontend_dir = File.join(File.dirname(__FILE__), "frontend")
  debug_log("Starting yarn dev in #{frontend_dir}")

  # Start yarn dev in a subprocess
  yarn_dev_pid = Process.spawn("yarn dev", chdir: frontend_dir)
  debug_log("Started yarn dev with PID #{yarn_dev_pid}")

  # Set up a trap to clean up the yarn dev process on exit
  at_exit do
    if yarn_dev_pid
      debug_log("Terminating yarn dev process (PID #{yarn_dev_pid})")
      Process.kill("TERM", yarn_dev_pid)
      Process.wait(yarn_dev_pid)
    end
  end
end

EM.run do
  debug_log("Starting application in #{DEBUG_MODE ? "DEBUG" : "NORMAL"} mode")
  debug_log("Environment variables - ARTISTE_SERVER: #{ENV["ARTISTE_SERVER"] || "mattermost"}")
  debug_log("Environment variables - MATTERMOST_URL: #{ENV["MATTERMOST_URL"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - MATTERMOST_TOKEN: #{ENV["MATTERMOST_TOKEN"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - MATTERMOST_CHANNELS: #{ENV["MATTERMOST_CHANNELS"] || "NOT SET"}")
  debug_log("Environment variables - DISCORD_TOKEN: #{ENV["DISCORD_TOKEN"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - DISCORD_CHANNELS: #{ENV["DISCORD_CHANNELS"] || "NOT SET"}")
  debug_log("Environment variables - ARTISTE_IMAGE_GENERATION: #{ENV["ARTISTE_IMAGE_GENERATION"] || "comfyu"}")
  debug_log("Environment variables - COMFYUI_URL: #{ENV["COMFYUI_URL"] || "http://localhost:8188"}")
  debug_log("Environment variables - COMFYUI_TOKEN: #{ENV["COMFYUI_TOKEN"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - CHUTES_TOKEN: #{ENV["CHUTES_TOKEN"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - ARTISTE_PEER_URL: #{ENV["ARTISTE_PEER_URL"] || "NOT SET"}")
  debug_log("Environment variables - ARTISTE_BROADCAST_CIDR: #{ENV["ARTISTE_BROADCAST_CIDR"] ? "SET" : "NOT SET"}")

  if options[:web].present?
    photos_dir = File.join(File.dirname(__FILE__), "db", "photos")
    web_app = PhotoGalleryApp.new(photos_dir, DEBUG_MODE)

    dispatch = Rack::Builder.app do
      if ENV["RACK_ENV"] == "development"
        use Rack::Static, urls: ["/photos"], root: File.join(File.dirname(__FILE__), "db"),
          header_rules: [[:all, {"Cache-Control" => "public, max-age=86400"}]]
      end

      assets_path = File.join(File.dirname(__FILE__), "assets")
      use Rack::Static, urls: ["/images", "/styles", "/javascript"], root: assets_path,
        header_rules: [[:all, {"Cache-Control" => "public, max-age=3600"}]]

      map "/" do
        run web_app
      end
    end

    server = Thin::Server.new("0.0.0.0", 4567, dispatch)
    server.start
  end

  server_strategy = ServerStrategy.create

  Signal.trap("INT") do
    debug_log("Received INT signal, shutting down...")
    # Terminate yarn dev process if it's running
    if yarn_dev_pid
      debug_log("Terminating yarn dev process (PID #{yarn_dev_pid})")
      Process.kill("TERM", yarn_dev_pid)
      Process.wait(yarn_dev_pid)
    end
    server.stop if defined?(server) && server
    EM.stop
  end

  Signal.trap("TERM") do
    debug_log("Received TERM signal, shutting down...")
    # Terminate yarn dev process if it's running
    if yarn_dev_pid
      debug_log("Terminating yarn dev process (PID #{yarn_dev_pid})")
      Process.kill("TERM", yarn_dev_pid)
      Process.wait(yarn_dev_pid)
    end
    server.stop if defined?(server) && server
    EM.stop
  end

  debug_log("Initialized #{ENV["ARTISTE_SERVER"] || "mattermost"} server and #{ENV["ARTISTE_IMAGE_GENERATION"] || "comfyui"} client")

  server_strategy.connect do |message|
    debug_log("Received message from #{ENV["ARTISTE_SERVER"] || "mattermost"} server")
    debug_log("Message data: #{message.inspect}") if DEBUG_MODE
    # Get or create user settings
    user_id = nil
    username = "unknown"
    if server_strategy.is_a?(MattermostServerStrategy)
      user_id = message.dig("data", "post", "user_id")
      username = message.dig("data", "channel_display_name")&.gsub(/@/, "") || message.dig("user", "username") || "unknown"
    elsif server_strategy.is_a?(DiscordServerStrategy)
      user_id = message["user"].id
      username = message["user"].username
    end

    debug_log("Processing message for user_id: #{user_id}, username: #{username}")

    user_settings = UserSettings.get_or_create_for_user(user_id, username)

    full_prompt = message["message"].gsub(/<?@\w+>?\s*/, "").strip
    debug_log("Extracted prompt: '#{full_prompt}'")

    if full_prompt.empty?
      server_strategy.respond(message, "Please provide a prompt for image generation!")
      next
    end

    # Parse the prompt/command first
    parsed_params = PromptParameterParser.parse(full_prompt, user_settings.parsed_prompt_params[:model])
    debug_log("Parsed parameters: #{parsed_params.inspect}")

    unless parsed_params.has_key?(:type)
      parsed_params[:type] = :generate
      debug_log("Assuming command is generate")
    end

    debug_log("Handling command of type: #{parsed_params[:type]}")
    EM.defer do
      CommandDispatcher.execute(server_strategy, message, parsed_params, user_settings, DEBUG_MODE)
    end
  end
end
