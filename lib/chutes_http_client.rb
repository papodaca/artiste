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
end
