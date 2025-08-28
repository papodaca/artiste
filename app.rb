require_relative "config/environment"
require_relative "lib/mattermost_server_strategy"
require_relative "lib/comfyui_client"


EM.run do
  mattermost = MattermostServerStrategy.new(
    mattermost_url: ENV["MATTERMOST_URL"],
    mattermost_token: ENV["MATTERMOST_TOKEN"],
    mattermost_channels: ENV.fetch("MATTERMOST_CHANNELS", "").split(",")
  )
  
  comfyui = ComfyuiClient.new(
    ENV["COMFYUI_URL"] || "http://localhost:8188",
    ENV["COMFYUI_TOKEN"],
    "workflow.json"
  )
  
  mattermost.connect do |message|
    prompt = message["message"].gsub(/@\w+\s*/, "").strip
    
    if prompt.empty?
      mattermost.respond(message, "Please provide a prompt for image generation!")
      next
    end
    
    reply = mattermost.respond(message, "🎨 Image generation queued...")
    
    EM.defer do
      begin
        mattermost.update(message, reply, "🎨 Generating image... This may take a few minutes.")
        
        result = comfyui.generate_and_wait(prompt)
        
        mattermost.update(
          message, 
          reply, 
          "", 
          result[:image_data], 
          result[:filename]
        )
      rescue => e
        error_msg = "❌ Image generation failed: #{e.message}"
        puts "Error generating image: #{e.message}"
        puts e.backtrace
        mattermost.update(message, reply, error_msg)
        mattermost.respond(reply, "```#{error_msg}\n#{e.backtrace.join("\n")}```")
      end
    end
  end
end
