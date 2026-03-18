MODELS_MAP = {
  "deepseek-r1" => "deepseek-ai/DeepSeek-R1-0528-TEE",
  "deepseek-v3" => "deepseek-ai/DeepSeek-V3.2-TEE",
  "glm-5" => "zai-org/GLM-5-TEE",
  "glm-5-flash" => "zai-org/GLM-5-Turbo",
  "glm-4" => "zai-org/GLM-4.7-TEE",
  "gpt-oss" => "openai/gpt-oss-120b-TEE",
  "llama" => "unsloth/Llama-3.2-3B-Instruct",
  "qwen-coder" => "Qwen/Qwen3-Coder-Next-TEE",
  "qwen" => "Qwen/Qwen3.5-397B-A17B-TEE"
}.freeze

class TextCommand < BaseCommand
  def self.parse(prompt)
    model = "gpt-oss"
    temperature = 0.7

    if (match = prompt.match(/(?:--model(?:=|\s+)|-m\s+)([^\s]+)/))
      model = match[1].to_s.downcase
    end

    if (match = prompt.match(/(?:--temperature(?:=|\s+)|-t\s+)(\d+.\d?)/))
      temperature = match[1].to_f
    end

    system_prompt = true
    if /--no-system/.match?(prompt)
      system_prompt = false
    end

    {
      model: MODELS_MAP[model] || MODELS_MAP["gpt-oss"],
      system_prompt: system_prompt,
      temperature: temperature,
      prompt: prompt
        .gsub(/--model\s+([^\s]+)/, "")
        .gsub("--no-system", "")
        .gsub(/(?:--temperature(?:=|\s+)|-t\s+)\d+.\d?/, "")
        .strip
    }
  end

  def execute
    debug_log("Handling text command")
    prompt = parsed_result[:prompt]
    model = parsed_result[:model]
    system_prompt = parsed_result[:system_prompt]
    temperature = parsed_result[:temperature]

    if prompt.nil? || prompt.strip.empty?
      debug_log("No prompt provided for text command")
      server.respond(message, "❌ Please provide a prompt for the text command.")
      return
    end

    debug_log("Generating text for prompt{#{model}}: #{prompt}")

    begin
      # First, send an initial response
      initial_response = "-thinking..."
      reply = server.respond(message, initial_response)

      # Then stream the response and update the message
      stream_text(prompt, reply, model, system_prompt, temperature)
    rescue => e
      debug_log("Error generating text: #{e.message}")
      server.respond(message, "❌ Sorry, I encountered an error while generating the text response.")
    end
  end

  private

  def stream_text(prompt, reply, model, has_system_prompt, temperature)
    if api_key.nil? || api_key.strip.empty?
      raise "OpenAI API key is not configured. Please set the OPENAI_API_KEY environment variable."
    end

    # Create OpenAI client
    client = OpenAI::Client.new(
      access_token: api_key,
      uri_base: api_url,
      timeout: 10
    )

    # Initialize the response text
    response_text = ""

    system_prompt = "you are artiste. you mostly do image generation but you dabble in the written word. use a poetic Iambic pentameter writing style. you are the queen of brevity, use as many emoji as possible."

    messages = []
    messages << {role: "system", content: system_prompt} if has_system_prompt
    messages << {role: "user", content: prompt}

    stream_proc = proc { |chunk, _bytesize|
      # Check for errors in the chunk
      if chunk.to_h.has_key?(:error)
        raise "API error: #{chunk.error.message}"
      end

      # Extract the content from the chunk
      content = chunk.dig("choices", 0, "delta", "content")

      # If there's content, append it to our response and update the message
      if content && content.length > 0
        response_text += content
        server.update(message, reply, response_text)
      end
    }

    # Stream the response
    client.chat(
      parameters: {
        model: model,
        stream: stream_proc,
        messages: messages,
        temperature: temperature
      }
    )

    # Final update to remove the thinking indicator if needed
    server.update(message, reply, response_text) if response_text != ""
  rescue => e
    debug_log("Error streaming text: #{e.message}")
    server.update(message, reply, "❌ Sorry, I encountered an error while generating the text response.")
  end

  def api_key
    @api_key ||= if ENV["OPENAI_API_KEY_ENV"].present?
      ENV[ENV["OPENAI_API_KEY_ENV"]]
    else
      ENV["OPENAI_API_KEY"]
    end
    @api_key
  end

  def api_url
    @api_url ||= ENV["OPENAI_API_URL"] || "https://api.openai.com/v1"
    @api_url
  end
end
