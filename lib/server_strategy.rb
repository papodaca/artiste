class ServerStrategy
  def self.create
    server_type = ENV.fetch("ARTISTE_SERVER", "mattermost").downcase

    case server_type
    when "discord"
      DiscordServerStrategy.new(
        discord_token: ENV["DISCORD_TOKEN"],
        discord_channels: (ENV["DISCORD_CHANNELS"] || "").split(",")
      )
    when "mattermost"
      MattermostServerStrategy.new(
        mattermost_url: ENV["MATTERMOST_URL"],
        mattermost_token: ENV["MATTERMOST_TOKEN"],
        mattermost_channels: ENV.fetch("MATTERMOST_CHANNELS", "").split(",")
      )
    else
      raise "Unsupported server type: #{server_type}. Supported types are 'mattermost' and 'discord'"
    end
  end

  def initialize(options)
    raise NotImplementedError
  end

  def connect(&block)
    raise NotImplementedError
  end

  def respond(message, reply)
    raise NotImplementedError
  end

  def update(message, reply, update)
    raise NotImplementedError
  end
end
