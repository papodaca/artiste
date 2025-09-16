class DiscordServerStrategy < ServerStrategy
  def initialize(*args, **kwargs)
    @discord_token = kwargs[:discord_token]
    @discord_channels = kwargs[:discord_channels] || []

    raise "Discord token is required" if @discord_token.nil? || @discord_token.empty?

    @bot = Discordrb::Bot.new(token: @discord_token)
    @bot_user = nil

    # Store the block for later use
    @message_handler = nil
  end

  def connect(&block)
    @message_handler = block

    # Set up event handlers
    @bot.ready do |event|
      @bot_user = @bot.profile
      puts "Discord bot connected as #{@bot_user.username}##{@bot_user.discriminator}"
    end

    @bot.mention do |event|
      handle_message(event)
    end

    @bot.message(in: @discord_channels) do |event|
      # Only respond to messages that mention the bot or are in allowed channels
      if event.message.content.include?(@bot_user&.mention) || @discord_channels.include?(event.channel.id)
        handle_message(event)
      end
    end

    # Start the bot (this will block)
    @bot.run(async: true)
  end

  def respond(message, reply)
    event = message["_event"]
    channel = event.channel
    response = event.respond(reply)

    # Return a hash similar to Mattermost's response format
    {
      "id" => response.id,
      "channel_id" => channel.id.to_s,
      "message" => reply,
      "response" => response
    }
  end

  def update(message, reply, update, file = nil, filename = nil)
    channel = message["channel"]
    response = reply["response"]

    if file && filename
      response.delete("status message")
      channel.send_file(file, caption: "", filename: filename)
    else
      response.edit(update)
    end
  end

  private

  def handle_message(event)
    return if event.user.bot_account? # Ignore other bots
    return unless @message_handler

    # Convert Discord event to a format similar to Mattermost
    message_data = {
      "event" => "posted",
      "_event" => event,
      "data" => {
        "post" => {
          "message" => event.message.content,
          "user_id" => event.user.id.to_s,
          "channel_id" => event.channel.id.to_s,
          "id" => event.message.id.to_s
        },
        "channel_type" => event.channel.pm? ? "D" : "O",
        "mentions" => extract_mentions(event.message.content)
      },
      "message" => event.message.content,
      "channel" => event.channel, # Store the actual channel object for responses
      "user" => event.user
    }

    # Check if bot is mentioned or if it's a DM or in allowed channels
    bot_mentioned = event.message.content.include?(@bot_user&.mention)
    is_dm = event.channel.pm?
    is_allowed_channel = @discord_channels.empty? || @discord_channels.include?(event.channel.id)

    if bot_mentioned || is_dm || is_allowed_channel
      @message_handler.call(message_data, event)
    end
  end

  def extract_mentions(content)
    # Extract user mentions from Discord message
    mentions = []
    content.scan(/<@!?(\d+)>/) do |user_id|
      mentions << user_id[0]
    end
    mentions << @bot_user.id.to_s if content.include?(@bot_user&.mention)
    mentions
  end
end
