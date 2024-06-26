require_relative "mattermost_client"
require_relative "server_strategy"

class MattermostServerStrategy < ServerStrategy
  def initialize(options)
    @options = options
    @mattermost_url = @options[:mattermost_url]
    @mattermost_token = @options[:mattermost_token]
    @mattermost_channels = @options[:mattermost_channels]

    @websocket_uri = URI.parse(@mattermost_url)
    @websocket_uri.scheme = (URI.parse(@mattermost_url).scheme == "https") ? "wss" : "ws"
    @websocket_uri.path = "/api/v4/websocket"

    @api_uri = URI.parse(@mattermost_url)
    @api_uri.path = "/api/v4"

    MattermostClient.setup(@api_uri.to_s, @mattermost_token)
    @client = MattermostClient

    get_self_user
  end

  def connect(&block)
    @messages_sequence = 0
    ws = WebSocket::EventMachine::Client.connect(
      uri: @websocket_uri.to_s,
      ssl: true,
      headers: {
        authorization: "Bearer #{@mattermost_token}"
      }
    )

    ws.onmessage do |msg, type|
      msg_data = JSON.parse(msg)
      @messages_sequence = msg["seq"]

      if msg_data["event"] == "posted"
        msg_data["data"]["mentions"] = JSON.parse(msg_data.dig("data", "mentions"))
        msg_data["data"]["post"] = JSON.parse(msg_data.dig("data", "post"))
        msg_data["message"] = msg_data.dig("data", "post", "message")

        if mentions.include?(@mattermost_bot_id) && (msg_data.dig("data", "channel_type") == "D" || @mattermost_channels.include?(msg_data.dig("data", "post", "channel_id")))
          yeild(msg_data)
        end
      end
    end

    ws.onclose do |code, reason|
      raise "socket closed"
    end
  end

  def respond(message, reply)
    body = {
      channel_id: message.dig("data", "channel_id"),
      message: reply
    }
    body[:root_id] = message.dig("data", "post", "id") if message.dig("data", "channel_type") != "D"
    @client.post(
      "/posts",
      headers: {
        "Content-Type" => "application/json"
      },
      body: body.to_json
    )
  end

  def update(message, reply, update, file = nil, filename = nil)
    body = {
      post_id: reply["id"],
      message: update
    }
    if !file.nil?
      # Final update has the final image!
      body[:file_ids] = upload_file(message.dig("data", "post", "channel_id"), file, filename)
    end
    @client.put(
      "/posts/#{reply["id"]}/patch",
      headers: {
        "Content-Type" => "application/json"
      },
      body: body.to_json
    )
  end

  private

  def get_self_user
    user_data = @client.get("/users/me")
    @mattermost_bot_id = user_data["id"]
  end

  def upload_file(channel_id, file, filename)
    query = {channel_id:}
    query[:filename] = filename if !filename.nil?
    new_files = @client.post(
      "/files",
      query:,
      body: file
    )
    new_files["file_infos"].map { |f| f["id"] }
  end
end

# event format
# {
#     "event": "posted",
#     "data": {
#         "channel_display_name": "Midjourney",
#         "channel_name": "midjourney",
#         "channel_type": "O",
#         "mentions": "[\"5afisnbo5bdbbe1n5t3mes95uc\"]",
#         "post": "{\"id\":\"8hnb6zw58tbr78yucpfswwix1r\",\"create_at\":1715988485716,\"update_at\":1715988485716,\"edit_at\":0,\"delete_at\":0,\"is_pinned\":false,\"user_id\":\"u8mi76cok7bn8jbb1uqjq4uate\",\"channel_id\":\"xke5ybictfrupx3f43asgc4a6h\",\"root_id\":\"\",\"original_id\":\"\",\"message\":\"@artiste test\",\"type\":\"\",\"props\":{\"disable_group_highlight\":true},\"hashtags\":\"\",\"pending_post_id\":\"u8mi76cok7bn8jbb1uqjq4uate:1715988485671\",\"reply_count\":0,\"last_reply_at\":0,\"participants\":null,\"metadata\":{}}",
#         "sender_name": "@papodaca",
#         "set_online": true,
#         "team_id": "ns58k6wm7bnamenhq353peatgh"
#     },
#     "broadcast": {
#         "omit_users": null,
#         "user_id": "",
#         "channel_id": "xke5ybictfrupx3f43asgc4a6h",
#         "team_id": "",
#         "connection_id": "",
#         "omit_connection_id": ""
#     },
#     "seq": 6
# }
# post
# {
# 	"id": "8hnb6zw58tbr78yucpfswwix1r",
# 	"create_at": 1715988485716,
# 	"update_at": 1715988485716,
# 	"edit_at": 0,
# 	"delete_at": 0,
# 	"is_pinned": false,
# 	"user_id": "u8mi76cok7bn8jbb1uqjq4uate",
# 	"channel_id": "xke5ybictfrupx3f43asgc4a6h",
# 	"root_id": "",
# 	"original_id": "",
# 	"message": "@artiste test",
# 	"type": "",
# 	"props": {
# 		"disable_group_highlight": true
# 	},
# 	"hashtags": "",
# 	"pending_post_id": "u8mi76cok7bn8jbb1uqjq4uate:1715988485671",
# 	"reply_count": 0,
# 	"last_reply_at": 0,
# 	"participants": null,
# 	"metadata": {
# 	}
# }

# private message
# {
#     "event": "posted",
#     "data": {
#         "channel_display_name": "@papodaca",
#         "channel_name": "5afisnbo5bdbbe1n5t3mes95uc__u8mi76cok7bn8jbb1uqjq4uate",
#         "channel_type": "D",
#         "mentions": "[\"5afisnbo5bdbbe1n5t3mes95uc\"]",
#         "post": "{\"id\":\"x3d9xk7y37rcmfymghpcgc17hy\",\"create_at\":1715989455294,\"update_at\":1715989455294,\"edit_at\":0,\"delete_at\":0,\"is_pinned\":false,\"user_id\":\"u8mi76cok7bn8jbb1uqjq4uate\",\"channel_id\":\"b4ri5qxk6ib1bkt65tb5mn1hkw\",\"root_id\":\"\",\"original_id\":\"\",\"message\":\"test\",\"type\":\"\",\"props\":{\"disable_group_highlight\":true},\"hashtags\":\"\",\"pending_post_id\":\"u8mi76cok7bn8jbb1uqjq4uate:1715989455253\",\"reply_count\":0,\"last_reply_at\":0,\"participants\":null,\"metadata\":{}}",
#         "sender_name": "@papodaca",
#         "set_online": true,
#         "team_id": ""
#     },
#     "broadcast": {
#         "omit_users": null,
#         "user_id": "",
#         "channel_id": "b4ri5qxk6ib1bkt65tb5mn1hkw",
#         "team_id": "",
#         "connection_id": "",
#         "omit_connection_id": ""
#     },
#     "seq": 10
# }
# post
# {
# 	"id": "x3d9xk7y37rcmfymghpcgc17hy",
# 	"create_at": 1715989455294,
# 	"update_at": 1715989455294,
# 	"edit_at": 0,
# 	"delete_at": 0,
# 	"is_pinned": false,
# 	"user_id": "u8mi76cok7bn8jbb1uqjq4uate",
# 	"channel_id": "b4ri5qxk6ib1bkt65tb5mn1hkw",
# 	"root_id": "",
# 	"original_id": "",
# 	"message": "test",
# 	"type": "",
# 	"props": {
# 		"disable_group_highlight": true
# 	},
# 	"hashtags": "",
# 	"pending_post_id": "u8mi76cok7bn8jbb1uqjq4uate:1715989455253",
# 	"reply_count": 0,
# 	"last_reply_at": 0,
# 	"participants": null,
# 	"metadata": {
# 	}
# }
