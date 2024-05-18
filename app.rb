require_relative "config/environment"
require_relative "lib/mattermost_server_strategy"

mattermost_url = ENV["MATTERMOST_URL"]
mattermost_token = ENV["MATTERMOTS_TOKEN"]

EM.run do
  mattermost = MattermostServerStrategy.new(
    {mattermost_url:, mattermost_token:}
  )
  mattermost.connect do |message|
    reply = mattermost.respond(message, "Image generation queued")
    mattermost.update(message, reply, "Image generation queued...")
  end
end
