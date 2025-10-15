class ImageGenerationClient
  # Static factory method to create the appropriate client
  def self.create
    client_type = ENV.fetch("ARTISTE_IMAGE_GENERATION", "comfyui").downcase
    case client_type
    when "comfyui"
      ComfyuiClient.new(
        ENV.fetch("COMFYUI_URL", "http://localhost:8188"),
        ENV["COMFYUI_TOKEN"]
      )
    when "chutes"
      ChutesClient.new(
        ENV["CHUTES_TOKEN"]
      )
    else
      raise "Unsupported client type: #{client_type}. Supported types are: comfyui, chutes"
    end
  end

  # Common interface methods that should be implemented by subclasses
  def generate(params, &block)
    raise NotImplementedError, "Subclasses must implement the generate method"
  end

  # Default implementation for generate_and_wait that can be overridden
  def generate_and_wait(params, max_wait_seconds = 1000, &block)
    # Default implementation just calls generate
    generate(params, &block)
  end

  protected

  attr_reader :http_client
end
