require_relative "config/environment"
require_relative "lib/mattermost_server_strategy"


EM.run do
  mattermost = MattermostServerStrategy.new(
    mattermost_url: ENV["MATTERMOST_URL"],
    mattermost_token: ENV["MATTERMOST_TOKEN"],
    mattermost_channels: ENV.fetch("MATTERMOST_CHANNELS", "").split(",")
  )
  mattermost.connect do |message|
    reply = mattermost.respond(message, "Image generation queued")
    mattermost.update(message, reply, "Image generation queued...")
  end
end
