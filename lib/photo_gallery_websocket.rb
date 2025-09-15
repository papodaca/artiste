require "websocket-eventmachine-server"
require "json"

class PhotoGalleryWebSocket
  class << self
    attr_accessor :connections

    def connections
      @connections ||= []
    end

    def start_server(host: "0.0.0.0", port: 4568)
      puts "Starting WebSocket server on #{host}:#{port}"

      EM.run do
        WebSocket::EventMachine::Server.start(host: host, port: port) do |ws|
          ws.onopen do
            connections << ws
          end

          ws.onmessage do |msg, type|
            handle_message(ws, msg, type)
          end

          ws.onclose do
            connections.delete(ws)
          end

          ws.onerror do |error|
            connections.delete(ws)
          end
        end

        puts "WebSocket server started on #{host}:#{port}"
      end
    end

    def broadcast(message)
      return if connections.empty?

      message_json = message.is_a?(String) ? message : message.to_json
      connections.each do |ws|
        begin
          ws.send(message_json)
        rescue
          connections.delete(ws)
        end
      end
    end

    def notify_new_photo(photo_path, task_data = nil)
      message = {
        type: "new_photo",
        photo_path: photo_path,
        photo_url: "/photo/#{photo_path}",
        task: task_data
      }
      broadcast(message)
    end

    def notify_photo_updated(photo_path, task_data = nil)
      message = {
        type: "photo_updated",
        photo_path: photo_path,
        photo_url: "/photo/#{photo_path}",
        task: task_data
      }
      broadcast(message)
    end

    private

    def handle_message(ws, msg, type)
      begin
        data = JSON.parse(msg)

        # Handle different message types here if needed
        case data["type"]
        when "ping"
          ws.send({ type: "pong", timestamp: Time.now.to_i }.to_json)
        end
      rescue JSON::ParserError
      end
    end
  end
end