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
  def generate_video(payload, &block)
    tries = 0
    response = retry_on_failure do
      tries += 1
      self.class.post("https://chutes-wan2-1-14b.chutes.ai/text2video",
        body: payload.to_json,
        timeout: 1000 * 1000)
    end

    if response.success?
      {
        video_data: response.body,
        prompt_id: response.headers["x-chutes-invocationid"]
      }
    else
      raise "Failed to generate video: #{response.code} - #{response.body}"
    end
  end

  # Generate video from image using Chutes API
  def generate_image2video(payload)
    response = self.class.post("https://chutes-wan2-1-14b.chutes.ai/image2video",
      body: payload.to_json,
      timeout: 1000 * 1000)

    if response.success?
      {
        video_data: response.body,
        prompt_id: response.headers["x-chutes-invocationid"]
      }
    else
      raise "Failed to generate video from image: #{response.code} - #{response.body}"
    end
  end

  private

  # Retry mechanism for specific error conditions
  def retry_on_failure(max_retries = 5, delay_seconds = 30)
    retries = 0

    loop do
      response = yield

      # Check if we need to retry based on status code and error message
      if should_retry?(response)
        retries += 1
        if retries <= max_retries
          sleep delay_seconds
          next
        end
      end

      return response
    end
  end

  # Determine if a response should trigger a retry
  def should_retry?(response)
    return false if response.success?

    # Check for status code 503 with specific error message
    if response.code == 503
      error_body = begin
        JSON.parse(response.body)
      rescue
        {}
      end
      error_detail = error_body["detail"] || ""
      return error_detail.include?("No instances available (yet)")
    end

    # Check for status code 29 with specific error message
    if response.code == 29
      error_body = begin
        JSON.parse(response.body)
      rescue
        {}
      end
      error_detail = error_body["detail"] || ""
      return error_detail.include?("Infrastructure is at maximum capacity")
    end

    false
  end
end
