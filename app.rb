#!/usr/bin/env ruby
require 'optparse'
require_relative "config/environment"
require_relative "config/database"
require_relative "lib/mattermost_server_strategy"
require_relative "lib/comfyui_client"
require_relative "lib/prompt_parameter_parser"

# Parse command line arguments
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"
  
  opts.on("-d", "--debug", "Enable debug mode") do |v|
    options[:debug] = v
  end
  
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Set debug flag globally
$DEBUG_MODE = options[:debug] || false

def debug_log(message)
  puts "[DEBUG] #{Time.now.strftime('%Y-%m-%d %H:%M:%S')} - #{message}" if $DEBUG_MODE
end

SYNONYMS = {
  "aspect_ratio" => ["ar", "aspectratio", "aspect_ratio"],
  "width" => ["w", "width"],
  "height" => ["h", "height"],
  "steps" => ["s", "steps"],
  "model" => ["m", "model"],
  "shift" => ["sh", "shift"],
  "basesize" => ["bs", "basesize"],
}.freeze

def synonym(name)
  SYNONYMS.each do |k, v|
    return k if v.include?(name.to_s)
  end
  nil
end


EM.run do
  debug_log("Starting application in #{$DEBUG_MODE ? 'DEBUG' : 'NORMAL'} mode")
  debug_log("Environment variables - MATTERMOST_URL: #{ENV['MATTERMOST_URL'] ? 'SET' : 'NOT SET'}")
  debug_log("Environment variables - MATTERMOST_TOKEN: #{ENV['MATTERMOST_TOKEN'] ? 'SET' : 'NOT SET'}")
  debug_log("Environment variables - MATTERMOST_CHANNELS: #{ENV['MATTERMOST_CHANNELS'] || 'NOT SET'}")
  debug_log("Environment variables - COMFYUI_URL: #{ENV['COMFYUI_URL'] || 'http://localhost:8188'}")
  debug_log("Environment variables - COMFYUI_TOKEN: #{ENV['COMFYUI_TOKEN'] ? 'SET' : 'NOT SET'}")
  
  mattermost = MattermostServerStrategy.new(
    mattermost_url: ENV["MATTERMOST_URL"],
    mattermost_token: ENV["MATTERMOST_TOKEN"],
    mattermost_channels: ENV.fetch("MATTERMOST_CHANNELS", "").split(",")
  )
  
  comfyui = ComfyuiClient.new(
    ENV["COMFYUI_URL"] || "http://localhost:8188",
    ENV["COMFYUI_TOKEN"],
    "workflows"
  )
  
  debug_log("Initialized Mattermost and ComfyUI clients")
  
  mattermost.connect do |message|
    debug_log("Received message from Mattermost")
    debug_log("Message data: #{message.inspect}") if $DEBUG_MODE
    # Get or create user settings
    user_id = message.dig("data", "post", "user_id")
    username = message.dig("data", "channel_display_name").gsub(/@/, "")
    
    debug_log("Processing message for user_id: #{user_id}, username: #{username}")
    
    user_settings = UserSettings.get_or_create_for_user(user_id, username)
    
    full_prompt = message["message"].gsub(/@\w+\s*/, "").strip
    debug_log("Extracted prompt: '#{full_prompt}'")
    
    if full_prompt.empty?
      mattermost.respond(message, "Please provide a prompt for image generation!")
      next
    end
    
    # Parse the prompt/command first
    parsed_params = PromptParameterParser.parse(full_prompt, user_settings.parsed_prompt_params[:model])
    debug_log("Parsed parameters: #{parsed_params.inspect}")
    
    # Handle commands
    if parsed_params.has_key?(:type)
      debug_log("Handling command of type: #{parsed_params[:type]}")
      handle_command(mattermost, message, parsed_params, user_settings)
    else
      debug_log("Handling image generation request")
      # Handle regular image generation
      reply = mattermost.respond(message, "🎨 Image generation queued...")
      
      EM.defer do
        begin
          debug_log("Starting image generation process")
          mattermost.update(message, reply, "🎨 Generating image... This may take a few minutes.")
          user_params = user_settings.parsed_prompt_params
          debug_log("User settings: #{user_params.inspect}")
          
          # Override with user-provided parameters
          final_params = PromptParameterParser.resolve_params(parsed_params.merge(user_params))
          debug_log("Final parameters for generation: #{final_params.inspect}")
          if $DEBUG_MODE
            mattermost.update(message, reply, "🎨 Generating image... This may take a few minutes. #{final_params.to_json}")
          end
          result = comfyui.generate_and_wait(final_params)
          debug_log("Image generation completed successfully")
          
          mattermost.update(
            message, 
            reply, 
            $DEBUG_MODE ? final_params.to_json : "",
            result[:image_data], 
            result[:filename]
          )
        rescue => e
          error_msg = "❌ Image generation failed: #{e.message}"
          puts "Error generating image: #{e.message}"
          puts e.backtrace
          debug_log("Image generation error: #{e.message}")
          debug_log("Error backtrace: #{e.backtrace.join("\n")}")
          mattermost.update(message, reply, error_msg)
          mattermost.respond(reply, "```#{error_msg}\n#{e.backtrace.join("\n")}```")
        end
      end
    end
  end

  # Command handling methods
  def handle_command(mattermost, message, parsed_result, user_settings)
    debug_log("Executing command handler for type: #{parsed_result[:type]}")
    case parsed_result[:type]
    when :set_settings
      handle_set_settings_command(mattermost, message, parsed_result, user_settings)
    when :get_settings
      handle_get_settings_command(mattermost, message, user_settings)
    when :help
      handle_help_command(mattermost, message, parsed_result)
    when :unknown_command
      handle_unknown_command(mattermost, message, parsed_result)
    else
      debug_log("Unknown command type encountered: #{parsed_result[:type]}")
      mattermost.respond(message, "❌ Unknown command type: #{parsed_result[:type]}")
    end
  end

  def handle_set_settings_command(mattermost, message, parsed_result, user_settings)
    debug_log("Handling set settings command")
    settings = parsed_result[:settings]
    delete_keys = parsed_result[:delete_keys] || []
    debug_log("Settings to update: #{settings.inspect}")
    debug_log("Keys to delete: #{delete_keys.inspect}")
    
    if settings.empty? && delete_keys.empty?
      debug_log("No settings or delete operations provided in command")
      mattermost.respond(message, "❌ No settings or delete operations provided. Use `/help` to see available options.")
      return
    end

    # Handle deletions first
    deleted_keys = []

    delete_keys.each do |key|
      debug_log("Deleting setting: #{key}")
      sym = synonym(key).to_sym
      if sym && user_settings.delete_param(sym)
        deleted_keys << sym.to_s.titleize
      end
    end

    # Update user settings
    # 
    if settings.has_key?(:aspect_ratio)
      debug_log("Aspect ratio detected, removing width/height settings")
      settings.delete(:width)
      settings.delete(:height)
    end
    settings.each do |key, value|
      debug_log("Setting #{key} = #{value}")
      user_settings.set_param(key.to_sym, value)
    end
    
    user_settings.save
    debug_log("User settings saved successfully")
    
    # Build response message
    response_parts = []
    
    if deleted_keys.any?
      response_parts << "🗑️ **Deleted settings:** #{deleted_keys.join(', ')}"
    end
    
    if settings.any?
      settings_text = []
      print_settings(settings_text, user_settings.parsed_prompt_params)
      response_parts << "✅ **Updated settings:**\n#{settings_text.join("\n")}"
    end
    
    if response_parts.empty?
      response_parts << "ℹ️ No changes made to settings."
    end
    
    response = response_parts.join("\n\n")
    mattermost.respond(message, response)
  end

  def handle_get_settings_command(mattermost, message, user_settings)
    debug_log("Handling get settings command")
    settings_text = []
    print_settings(settings_text, user_settings.parsed_prompt_params)
    debug_log("Retrieved user settings: #{user_settings.parsed_prompt_params.inspect}")
    
    mattermost.respond(message, "⚙️ **Current Settings:**\n#{settings_text.join("\n")}")
  end

  def print_settings(out, settings)
    out << "```"
    settings.each do |key, value|
      out << "#{key.to_s.titleize}: #{value}"
    end
    out << "```"
  end

  def handle_help_command(mattermost, message, parsed_result)
    debug_log("Handling help command")
    help_text = parsed_result[:help_text]
    mattermost.respond(message, help_text)
  end

  def handle_unknown_command(mattermost, message, parsed_result)
    debug_log("Handling unknown command")
    error_msg = parsed_result[:error] || "Unknown command"
    debug_log("Unknown command error: #{error_msg}")
    mattermost.respond(message, "❌ #{error_msg}")
  end
end
