require "httparty"

class ComfyuiHttpClient
  include HTTParty

  def initialize(base_url, token = nil)
    @base_url = base_url
    @token = token

    self.class.base_uri(@base_url)

    # Set default headers
    default_headers = {"content-type" => "application/json"}
    default_headers["Authorization"] = "Bearer #{token}" if token
    self.class.headers(default_headers)
  end

  # Queue a prompt for image generation
  def queue_prompt(workflow)
    response = self.class.post("/prompt",
      body: {prompt: workflow}.to_json)

    if response.success?
      response.parsed_response
    else
      raise "Failed to queue prompt: #{response.code} - #{response.body}"
    end
  end

  # Check the status of a prompt
  def get_prompt_status(prompt_id)
    response = self.class.get("/history/#{prompt_id}")

    if response.success?
      response.parsed_response
    else
      raise "Failed to get prompt status: #{response.code} - #{response.body}"
    end
  end

  # Get prompt queue
  def get_prompt_queue
    response = self.class.get("/queue")

    if response.success?
      response.parsed_response
    else
      raise "Failed to get prompt queue: #{response.code} - #{response.body}"
    end
  end

  # Get generated image
  def get_image(filename, subfolder = "", type = "output")
    response = self.class.get("/view",
      query: {
        filename: filename,
        subfolder: subfolder,
        type: type
      })

    if response.success?
      response.body
    else
      raise "Failed to get image: #{response.code} - #{response.body}"
    end
  end
end
