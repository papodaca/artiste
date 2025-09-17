MODELS_MAP = {
  "deepseek-r1" => "deepseek-ai/DeepSeek-R1",
  "deepseek-v3" => "deepseek-ai/DeepSeek-V3.1",
  "glm-4.5" => "zai-org/GLM-4.5-FP8",
  "glm-4" => "zai-org/GLM-4-32B-0414",
  "gpt-oss" => "openai/gpt-oss-120b",
  "llama" => "nvidia/Llama-3_3-Nemotron-Super-49B-v1_5",
  "qwen-coder" => "Qwen/Qwen3-Coder-480B-A35B-Instruct-FP8",
  "qwen" => "Qwen/Qwen3-235B-A22B-Instruct-2507"
}.freeze

class TextCommand < BaseCommand
  def self.parse(prompt)
    model = "qwen"
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
      model: MODELS_MAP[model] || MODELS_MAP["qwen"],
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
    # Get API configuration from environment variables
    api_key = ENV["OPENAI_API_KEY"]
    api_url = ENV["OPENAI_API_URL"] || "https://api.openai.com/v1"

    # Validate API key
    if api_key.nil? || api_key.strip.empty?
      raise "OpenAI API key is not configured. Please set the OPENAI_API_KEY environment variable."
    end

    # Create OpenAI client
    client = OpenAI::Client.new(
      api_key: api_key,
      base_url: api_url,
      timeout: 10
    )

    # Initialize the response text
    response_text = ""

    system_prompt = "you are artiste. you mostly do image generation but you dabble in the written word. use a poetic Iambic pentameter writing style. you are the queen of brevity, use as many emoji as possible."

    messages = []
    messages << {role: "system", content: system_prompt} if has_system_prompt
    messages << {role: "user", content: prompt}

    # Stream the response
    stream = client.chat.completions.stream_raw(
      model: model,
      messages: messages,
      temperature: temperature
    )

    # Process each chunk of the stream
    stream.each do |chunk|
      # Check for errors in the chunk
      if chunk.to_h.has_key?(:error)
        raise "API error: #{chunk.error.message}"
      end

      # Extract the content from the chunk
      content = chunk.choices&.first&.delta&.content

      # If there's content, append it to our response and update the message
      if content
        response_text += content
        server.update(message, reply, response_text)
      end
    end

    # Final update to remove the thinking indicator if needed
    server.update(message, reply, response_text) if response_text != ""
  rescue => e
    debug_log("Error streaming text: #{e.message}")
    server.update(message, reply, "❌ Sorry, I encountered an error while generating the text response.")
  end
end
