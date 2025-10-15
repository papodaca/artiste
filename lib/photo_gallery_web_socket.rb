class PhotoGalleryWebSocket
  class << self
    def connections
      @connections ||= []
    end

    def start_server(host: "0.0.0.0", port: 4568)
      connections # Initialize connections
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
      if ENV["ARTISTE_PEER_URL"]
        forward_to_peer(message)
      else
        # Normal mode: broadcast to local connections
        local_broadcast(message)
      end
    end

    def local_broadcast(message)
      return if connections.empty?

      message_json = message.is_a?(String) ? message : message.to_json
      connections.each do |ws|
        ws.send(message_json)
      rescue
        connections.delete(ws)
      end
    end

    def forward_to_peer(message)
      peer_url = ENV["ARTISTE_PEER_URL"]
      return unless peer_url

      begin
        uri = URI.parse("#{peer_url}/api/broadcast")

        http = Net::HTTP.new(uri.host, uri.port)
        headers = {"Content-Type" => "application/json"}
        token = ENV["ARTISTE_PEER_TOKEN"]
        headers["Authorization"] = "Bearer #{token}" if token
        request = Net::HTTP::Post.new(uri.path, headers)
        request.body = message.to_json

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
      
      rendered_content = render_photo_item_stream(rel_path, photo_id)
      
      message = {
        type: "new_photo",
        photo_path: rel_path,
        photo_url: "/photos/#{rel_path}",
        task: task_data,
        html: rendered_content
      }
      broadcast(message)
    end

    def notify_photo_updated(photo_path, task_data = nil)
      rel_path = photo_path.gsub(/^db\/photos\//, "")
      photo_id = task_data&.dig("id") || task_data&.dig(:id)
      
      rendered_content = render_photo_item_stream(rel_path, photo_id)
      
      message = {
        type: "photo_updated",
        photo_path: rel_path,
        photo_url: "/photos/#{rel_path}",
        task: task_data,
        html: rendered_content
      }
      broadcast(message)
    end

    def render_photo_item_stream(photo_path, photo_id)
      # Render the ERB template
      template = Tilt::ERBTemplate.new(File.join(File.dirname(__FILE__), "..", "views", "photo_item_stream.erb"))
      
      # Create a context object with helper methods
      context = Object.new
      class << context
        include Sinatra::Helpers
        
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
      end
      
      # Render the template with the required locals
      template.render(context, photo_path: photo_path, photo_id: photo_id)
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
  end
end
