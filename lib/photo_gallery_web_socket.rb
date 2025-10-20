require "openssl"
require "base64"

class PhotoGalleryWebSocket
  class RenderContext
    include Sinatra::Helpers

    attr_reader :connection

    def initialize(connection)
      @connection = connection
    end

    def erb(template_name, options = {})
      template_path = File.join(File.dirname(__FILE__), "..", "views", "#{template_name}.erb")
      Tilt::ERBTemplate.new(template_path).render(self, options[:locals] || {})
    end

    def get_filename(path)
      path.split("/").last
    end

    def is_video(path)
      path.downcase.end_with?(".mp4")
    end

    def current_user_admin?
      ENV["ARTISTE_ADMINS"].split(",").map(&:strip).include?(connection.user_id)
    end

    def current_user_authenticated?
      connection.user_id.present?
    end

    def current_user_id
      connection.user_id
    end
  end

  class Connection
    attr_accessor :websocket, :user_id, :session_data

    def initialize(websocket)
      @websocket = websocket
      @user_id = nil
      @session_data = nil
    end

    def authenticated?
      !@user_id.nil?
    end
  end

  class << self
    def connections
      @connections ||= []
    end

    def session_secret
      @session_secret ||= ENV["SESSION_SECRET"]
    end

    def start_server(host: "0.0.0.0", port: 4568)
      connections # Initialize connections
      puts "Starting WebSocket server on #{host}:#{port}"

      EM.run do
        WebSocket::EventMachine::Server.start(host: host, port: port) do |ws|
          ws.onopen do |handshake|
            connection = Connection.new(ws)

            if handshake.headers.has_key?("cookie")
              connection.user_id = extract_user_id_from_cookie(handshake.headers["cookie"])
            end
            connections << connection
          end

          ws.onmessage do |msg, type|
            handle_message(ws, msg, type)
          end

          ws.onclose do
            connections.delete_if { |conn| conn.websocket == ws }
          end

          ws.onerror do |error|
            connections.delete_if { |conn| conn.websocket == ws }
          end
        end

        puts "WebSocket server started on #{host}:#{port}"
      end
    end

    def broadcast(message, target_user_id = nil)
      if ENV["ARTISTE_PEER_URL"]
        forward_to_peer(message, target_user_id)
      else
        # Normal mode: broadcast to local connections
        local_broadcast(message, target_user_id)
      end
    end

    def local_broadcast(message, target_user_id = nil)
      return if connections.empty?

      connections.each do |conn|
        message_text = render_photo_item_stream(message, conn)
        message_json = {}.merge(message).merge(html: message_text).to_json
        if target_user_id.nil? || conn.user_id == target_user_id
          conn.websocket.send(message_json)
        end
      rescue => e
        puts "Error broadcasting message: #{e.message}"
        connections.delete(conn)
      end
    end

    def forward_to_peer(message, target_user_id = nil)
      peer_url = ENV["ARTISTE_PEER_URL"]
      return unless peer_url

      begin
        uri = URI.parse("#{peer_url}/api/broadcast")

        http = Net::HTTP.new(uri.host, uri.port)
        headers = {"Content-Type" => "application/json"}
        token = ENV["ARTISTE_PEER_TOKEN"]
        headers["Authorization"] = "Bearer #{token}" if token
        request = Net::HTTP::Post.new(uri.path, headers)

        # Include target_user_id in the forwarded message
        payload = message.merge(target_user_id: target_user_id) if target_user_id
        request.body = (payload || message).to_json

        response = http.request(request)

        if !response.is_a?(Net::HTTPSuccess)
          puts "Failed to forward message to peer: #{response.code} #{response.message}"
        end
      rescue => e
        puts "Error forwarding message to peer: #{e.message}"
      end
    end

    def notify_new_photo(photo_path, task_data = nil)
      rel_path = photo_path.gsub(/^db\/photos\//, "")
      photo_id = task_data&.dig("id") || task_data&.dig(:id)
      is_private = task_data&.dig("private") || task_data&.dig(:private)
      user_id = task_data&.dig("user_id") || task_data&.dig(:user_id)

      message = {
        type: "new_photo",
        photo_path: rel_path,
        photo_id:,
        is_private:,
        user_id:,
        photo_url: "/photos/#{rel_path}",
        task: task_data
      }

      # If photo is private, only broadcast to the owner
      if is_private
        broadcast(message, user_id)
      else
        broadcast(message)
      end
    end

    def render_photo_item_stream(message, connection)
      template = Tilt::ERBTemplate.new(File.join(File.dirname(__FILE__), "..", "views", "photo_item_stream.erb"))
      context = RenderContext.new(connection)

      template.render(
        context, photo: {
          path: message[:photo_path],
          id: message[:photo_id],
          is_deleted: false,
          is_private: message[:is_private],
          owner_id: message[:user_id]
        }
      )
    end

    private

    def handle_message(ws, msg, type)
      data = JSON.parse(msg)

      # Handle different message types here if needed
      case data["type"]
      when "ping"
        ws.send({type: "pong", timestamp: Time.now.to_i}.to_json)
      end
    rescue JSON::ParserError
    end

    # Extract user_id from session cookie
    def extract_user_id_from_cookie(cookie_header)
      return nil unless cookie_header
      return nil unless session_secret

      # Parse the cookie header to find the rack.session cookie
      cookies = cookie_header.split(";").map(&:strip)
      session_cookie = cookies.find { |c| c.start_with?("rack.session=") }

      return nil unless session_cookie

      # Extract the session data
      session_data = session_cookie.sub("rack.session=", "")

      # Decode the session data (it's base64 encoded and encrypted)
      begin
        encryptor = Rack::Session::Encryptor.new(session_secret)
        data = encryptor.decrypt(CGI.unescape(session_data))
        if data.has_key?("user_info")
          user_info = JSON.load(data["user_info"])
          return user_info["id"]
        end
      rescue => e
        puts "Error decoding session: #{e.message}"
        puts e.backtrace.first(5).join("\n")
      end

      nil
    end
  end
end
