class ChutesHttpClient
  include HTTParty

  def initialize(base_url = "https://image.chutes.ai", token = nil)
    @base_url = base_url
    @token = token

    self.class.base_uri(@base_url)

    # Set default headers
    default_headers = {"content-type" => "application/json"}
    default_headers["Authorization"] = "Bearer #{token}" if token
    self.class.headers(default_headers)
  end

  # Generate image using Chutes API
  def generate_image(payload)
    response = self.class.post("/generate",
      body: payload.to_json)

    if response.success?
      {
        image_data: response.body,
        prompt_id: response.headers["x-chutes-invocationid"]
      }
    else
      raise "Failed to generate image: #{response.code} - #{response.body}"
    end
  end

  # Generate image edit using Chutes API (different endpoint)
  def generate_image_edit(payload)
    # Use the specific edit endpoint from the curl example
    response = self.class.post("https://chutes-qwen-image-edit-2509.chutes.ai/generate",
      body: payload.to_json,
      timeout: 500)

    if response.success?
      {
        image_data: response.body,
        prompt_id: response.headers["x-chutes-invocationid"]
      }
    else
      raise "Failed to generate image edit: #{response.code} - #{response.body}"
    end
  end

  # Generate video using Chutes API
  def generate_video(payload)
    response = self.class.post("https://chutes-wan2-1-14b.chutes.ai/text2video",
      body: payload.to_json,
      timeout: 1000 * 1000)

    if response.success?
      {
        video_data: response.body,
        prompt_id: response.headers["x-chutes-invocationid"]
      }
    else
      raise "Failed to generate video: #{response.code} - #{response.body}"
    end
  end
end
