#!/usr/bin/env ruby
require "optparse"
require "fileutils"
require_relative "config/environment"

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
DEBUG_MODE = (options[:debug] || false).freeze

def debug_log(message)
  puts "[DEBUG] #{Time.now.strftime("%Y-%m-%d %H:%M:%S")} - #{message}" if DEBUG_MODE
end

EM.run do
  debug_log("Starting application in #{DEBUG_MODE ? "DEBUG" : "NORMAL"} mode")
  debug_log("Environment variables - ARTISTE_SERVER: #{ENV["ARTISTE_SERVER"] || "mattermost"}")
  debug_log("Environment variables - MATTERMOST_URL: #{ENV["MATTERMOST_URL"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - MATTERMOST_TOKEN: #{ENV["MATTERMOST_TOKEN"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - MATTERMOST_CHANNELS: #{ENV["MATTERMOST_CHANNELS"] || "NOT SET"}")
  debug_log("Environment variables - DISCORD_TOKEN: #{ENV["DISCORD_TOKEN"] ? "SET" : "NOT SET"}")
  debug_log("Environment variables - DISCORD_CHANNELS: #{ENV["DISCORD_CHANNELS"] || "NOT SET"}")
  debug_log("Environment variables - COMFYUI_URL: #{ENV["COMFYUI_URL"] || "http://localhost:8188"}")
  debug_log("Environment variables - COMFYUI_TOKEN: #{ENV["COMFYUI_TOKEN"] ? "SET" : "NOT SET"}")

  photos_dir = File.join(File.dirname(__FILE__), "db", "photos")
  web_app = PhotoGalleryApp.new(photos_dir)

  dispatch = Rack::Builder.app do
    map "/" do
      run web_app
    end
  end

  server = Thin::Server.new("0.0.0.0", 4567, dispatch)
  server.start

  server_strategy = ServerStrategy.create_strategy

  comfyui = ComfyuiClient.new(
    ENV["COMFYUI_URL"] || "http://localhost:8188",
    ENV["COMFYUI_TOKEN"],
    "workflows"
  )

  Signal.trap("INT") do
    server.stop
    EM.stop
  end

  Signal.trap("TERM") do
    server.stop
    EM.stop
  end

  debug_log("Initialized #{ENV["ARTISTE_SERVER"] || "mattermost"} server and ComfyUI clients")

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

    # Handle commands
    if parsed_params.has_key?(:type)
      debug_log("Handling command of type: #{parsed_params[:type]}")
      CommandDispatcher.execute(server_strategy, message, parsed_params, user_settings, DEBUG_MODE)
    else
      debug_log("Handling image generation request")
      # Handle regular image generation
      reply = server_strategy.respond(message, "🎨 Image generation queued...")

      # Create generation task record
      user_params = user_settings.parsed_prompt_params
      final_params = PromptParameterParser.resolve_params(parsed_params.merge(user_params))

      generation_task = GenerationTask.create(
        user_id: user_id,
        username: username,
        prompt: full_prompt,
        parameters: final_params.to_json,
        workflow_type: final_params[:model] || "flux",
        status: "pending"
      )
      debug_log("Created generation task ##{generation_task.id}")

      EM.defer do
        debug_log("Queued image generation process for task ##{generation_task.id}")

        debug_log("User settings: #{user_params.inspect}")
        debug_log("Final parameters for generation: #{final_params.inspect}")

        result = comfyui.generate_and_wait(final_params, 1.hour.seconds.to_i) do |kind, comfyui_prompt_id, progress|
          if comfyui_prompt_id.present? && comfyui_prompt_id != generation_task.comfyui_prompt_id
            debug_log("Setting the generation task's comfyui_prompt_id to #{comfyui_prompt_id}")
            generation_task.comfyui_prompt_id = comfyui_prompt_id
            generation_task.save
          end
          if kind == :running
            debug_log("Starting image generation process for task ##{generation_task.id}")
            generation_task.mark_processing
            server_strategy.update(message, reply, "🎨 Generating image... This may take a few minutes.#{DEBUG_MODE ? final_params.to_json : ""}")
          end
          if kind == :progress
            debug_log("Generation progress for task ##{generation_task.id}, #{progress.join(", ")}")
            server_strategy.update(message, reply, "🎨 Generating image... This may take a few minutes. progressing: #{progress.map { |p| p.to_s + "%" }.join(", ")}.#{DEBUG_MODE ? final_params.to_json : ""}")
          end
        end
        debug_log("Image generation completed successfully for task ##{generation_task.id}")

        filename = result[:filename]
        generation_task.mark_completed(filename)
        target_dir = generation_task.file_path
        filepath = File.join(target_dir, filename)
        File.write(filepath, result[:image_data])

        Kernel.system("exiftool -config exiftool_config -PNG:prompt=\"#{generation_task.prompt}\" -overwrite_original #{filepath} > /dev/null 2>&1")

        exif_data = {}
        debug_log("Reading EXIF data from image file: #{filepath}")
        exif_output = `exiftool -j "#{filepath}" 2>/dev/null`
        begin
          exif_json = JSON.parse(exif_output)
          if exif_json.is_a?(Array) && exif_json.first
            exif_data = exif_json.first
            %w[SourceFile ExifToolVersion FileName Directory FilePermissions FileModifyDate FileAccessDate FileInodeChangeDate].each do |k|
              exif_data.delete(k)
            end
            debug_log("Successfully read EXIF data from image")
          end
        rescue JSON::ParserError => e
          debug_log("Failed to parse EXIF JSON: #{e.message}")
        end

        unless exif_data.empty?
          generation_task.set_exif_data(exif_data)
        end

        server_strategy.update(
          message,
          reply,
          DEBUG_MODE ? final_params.to_json : "",
          File.open(filepath, "rb"),
          filepath
        )
      rescue => e
        error_msg = "❌ Image generation failed: #{e.message}"
        puts "Error generating image: #{e.message}"
        puts e.backtrace
        debug_log("Image generation error: #{e.message}")
        debug_log("Error backtrace: #{e.backtrace.join("\n")}")

        # Mark task as failed
        generation_task.mark_failed(e.message)

        server_strategy.update(message, reply, error_msg)
        server_strategy.respond(message, "```#{error_msg}\n#{e.backtrace.join("\n")}```")
      end
    end
  end
end
