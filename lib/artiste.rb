class Artiste
  include Logging

  def initialize(options)
    @options = options
    Logging.level = (options[:debug] || options[:dev]) ? Logger::DEBUG : Logger::INFO
  end

  def start
    EM.run do
      info "Starting application"
      debug "Environment variables - ARTISTE_SERVER: #{ENV["ARTISTE_SERVER"] || "mattermost"}"
      debug "Environment variables - MATTERMOST_URL: #{ENV["MATTERMOST_URL"] ? "SET" : "NOT SET"}"
      debug "Environment variables - MATTERMOST_TOKEN: #{ENV["MATTERMOST_TOKEN"] ? "SET" : "NOT SET"}"
      debug "Environment variables - MATTERMOST_CHANNELS: #{ENV["MATTERMOST_CHANNELS"] || "NOT SET"}"
      debug "Environment variables - DISCORD_TOKEN: #{ENV["DISCORD_TOKEN"] ? "SET" : "NOT SET"}"
      debug "Environment variables - DISCORD_CHANNELS: #{ENV["DISCORD_CHANNELS"] || "NOT SET"}"
      debug "Environment variables - ARTISTE_IMAGE_GENERATION: #{ENV["ARTISTE_IMAGE_GENERATION"] || "comfyui"}"
      debug "Environment variables - COMFYUI_URL: #{ENV["COMFYUI_URL"] || "http://localhost:8188"}"
      debug "Environment variables - COMFYUI_TOKEN: #{ENV["COMFYUI_TOKEN"] ? "SET" : "NOT SET"}"
      debug "Environment variables - CHUTES_TOKEN: #{ENV["CHUTES_TOKEN"] ? "SET" : "NOT SET"}"
      debug "Environment variables - ARTISTE_PEER_URL: #{ENV["ARTISTE_PEER_URL"] || "NOT SET"}"
      debug "Environment variables - ARTISTE_BROADCAST_CIDR: #{ENV["ARTISTE_BROADCAST_CIDR"] ? "SET" : "NOT SET"}"

      start_web_server if @options[:web]

      @server_strategy = ServerStrategy.create
      trap_signals

      info "Initialized #{ENV["ARTISTE_SERVER"] || "mattermost"} server and #{ENV["ARTISTE_IMAGE_GENERATION"] || "comfyui"} client"

      @server_strategy.connect do |message|
        debug "Received message from #{ENV["ARTISTE_SERVER"] || "mattermost"} server"
        debug "Message data: #{message.inspect}"

        user_id, username = extract_user(message)
        debug "Processing message for user_id: #{user_id}, username: #{username}"

        user_settings = UserSettings.get_or_create_for_user(user_id, username)

        full_prompt = message["message"].gsub(/<?@\w+>?\s*/, "").strip
        debug "Extracted prompt: '#{full_prompt}'"

        if full_prompt.empty?
          @server_strategy.respond(message, "Please provide a prompt for image generation!")
          next
        end

        parsed_params = PromptParameterParser.parse(full_prompt, user_settings.parsed_prompt_params[:model])
        parsed_params[:type] ||= :generate
        debug "Handling command: #{parsed_params[:type]} — #{parsed_params.inspect}"

        EM.defer do
          CommandDispatcher.execute(@server_strategy, message, parsed_params, user_settings)
        end
      end
    end
  rescue RuntimeError => e
    warn "Stopped: #{e.message}"
  end

  private

  def start_web_server
    photos_dir = File.expand_path("../../db/photos", __FILE__)
    web_app = PhotoGalleryApp.new(photos_dir)

    dispatch = Rack::Builder.app do
      if ENV["RACK_ENV"] == "development"
        use Rack::Static, urls: %w[/photos /music], root: File.expand_path("../../db", __FILE__),
          header_rules: [[:all, {"Cache-Control" => "public, max-age=86400"}]]
      end

      assets_path = File.expand_path("../../assets", __FILE__)
      use Rack::Static, urls: %w[/images /styles /javascript], root: assets_path,
        header_rules: [[:all, {"Cache-Control" => "public, max-age=3600"}]]

      map "/" do
        run web_app
      end
    end

    @web_server = Thin::Server.new("0.0.0.0", 4567, dispatch)
    @web_server.start
  end

  def trap_signals
    Signal.trap("INT") { shutdown }
    Signal.trap("TERM") { shutdown }
  end

  def shutdown
    info "Shutting down..."
    @web_server&.stop
    EM.stop
  end

  def extract_user(message)
    if @server_strategy.is_a?(MattermostServerStrategy)
      user_id = message.dig("data", "post", "user_id")
      username = message.dig("data", "channel_display_name")&.gsub(/@/, "") || message.dig("user", "username") || "unknown"
    elsif @server_strategy.is_a?(DiscordServerStrategy)
      user_id = message["user"].id
      username = message["user"].username
    end
    [user_id, username]
  end
end
