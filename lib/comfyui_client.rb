require "fileutils"
require "cgi"

class ComfyuiClient
  include HTTParty

  def initialize(comfyui_url, token = nil, workflow_path = 'workflows')
    @base_url = comfyui_url
    @token = token
    @workflow_path = workflow_path
    
    self.class.base_uri(@base_url)
    
    # Don't set headers globally, we'll set them per request
  end

  # Queue a prompt for image generation
  def queue_prompt(workflow)
    headers = { 'content-type' => 'application/json' }
    headers['Authorization'] = "Bearer #{@token}" if @token
    
    response = self.class.post('/prompt', 
      headers: headers,
      body: { prompt: workflow }.to_json
    )
    
    if response.success?
      response.parsed_response
    else
      raise "Failed to queue prompt: #{response.code} - #{response.body}"
    end
  end

  # Check the status of a prompt
  def get_prompt_status(prompt_id)
    headers = {}
    headers['Authorization'] = "Bearer #{@token}" if @token
    
    response = self.class.get("/history/#{prompt_id}", 
      headers: headers.empty? ? nil : headers
    )
    
    if response.success?
      response.parsed_response
    else
      raise "Failed to get prompt status: #{response.code} - #{response.body}"
    end
  end

  def get_propt_queue
    headers = {}
    headers['Authorization'] = "Bearer #{@token}" if @token
    
    response = self.class.get("/queue", 
      headers: headers.empty? ? nil : headers
    )
    
    if response.success?
      response.parsed_response
    else
      raise "Failed to get prompt status: #{response.code} - #{response.body}"
    end
  end

  # Get generated image
  def get_image(filename, subfolder = "", type = "output")
    headers = {}
    headers['Authorization'] = "Bearer #{@token}" if @token
    
    response = self.class.get("/view", 
      headers: headers.empty? ? nil : headers,
      query: { 
        filename: filename, 
        subfolder: subfolder, 
        type: type 
      }
    )
    
    if response.success?
      response.body
    else
      raise "Failed to get image: #{response.code} - #{response.body}"
    end
  end

  def connect_websocket(prompt_id, &block)
    ws_url = @base_url.gsub(/^http?/, 'ws')
    ws_url = "#{ws_url}/ws?token=#{CGI.escape(@token)}"
    ws =  WebSocket::EventMachine::Client.connect(uri: ws_url)

    ws.onmessage do |msg, type|
      begin
        data = JSON.parse(msg)
        block&.call(data) if data.dig("data", "prompt_id") == prompt_id 
      rescue JSON::ParserError => e
      end
    end
    
    ws.onclose do |code, reason|
      ws = nil
    end
    ws
  end

  # Load workflow template from JSON file
  def load_workflow_template(workflow_path)
    if File.exist?(workflow_path)
      JSON.parse(File.read(workflow_path))
    else
      raise "Workflow file not found: #{workflow_path}"
    end
  end


  # Create workflow from template with parameter injection  
  def create_workflow_from_template(model, params)
    workflow = load_workflow_template("#{@workflow_path}/workflow_#{model}.json")
    
    # Remove x-params from the workflow as it's only for our reference
    x_params = workflow.delete("x-params")

    output = x_params.delete("output")

    raise "Workflow file does not contain expected options" if x_params.nil? || output.nil?
    
    # Set parameters using x-params mapping
    x_params.each do |param_key, node_id|
      next unless workflow[node_id]
      
      param_symbol = param_key.to_sym
      next unless params.key?(param_symbol)
      
      value = params[param_symbol]
      
      # Handle special cases
      if %w[prompt negative_prompt].include?(param_key)
        workflow[node_id]["inputs"]["text"] = value.to_s
      else
        workflow[node_id]["inputs"]["value"] = value
      end
    end
    
    [workflow, output]
  end

  # Create workflow from clean prompt and params hash
  def create_workflow_from_params(params)
    workflow, output = create_workflow_from_template(params[:model], params)
    [workflow, params.merge({output: output})]
  end

  # Poll for completion and return the generated image with clean prompt and params
  def generate_and_wait(params, max_wait_seconds = 1000, &block)
    workflow, params = create_workflow_from_params(params)
    result = queue_prompt(workflow)
    prompt_id = result["prompt_id"]
    
    if prompt_id.nil?
      raise "Failed to get prompt ID from ComfyUI response: #{result}"
    end
    
    start_time = nil

    block.call(:queued, prompt_id, nil) if block_given?
    progress = []
    ws = connect_websocket(prompt_id) do |message|
      if message["type"] == "progress"
        value = message.dig("data", "value")
        max = message.dig("data", "max")
        percent = (value.to_f / max.to_f * 100).round

        if progress.empty? || (progress.last == 100 && percent < 100)
          progress << percent
        elsif progress.last < 100
          progress[progress.length - 1] = percent
        end

        block&.call(:progress, prompt_id, progress) if block_given?
      end
    end
    
    loop do
      if start_time.present? && Time.now - start_time > max_wait_seconds
        raise "Image generation timed out after #{max_wait_seconds} seconds"
      end

      queue = get_propt_queue

      states = queue["queue_running"].map do |a|
        a[1] == prompt_id
      end

      if states.any?(true) && start_time.nil?
        start_time = Time.now
        block.call(:running, prompt_id, nil) if block_given?
      end

      status = get_prompt_status(prompt_id)

      if status&.dig(prompt_id, "status", "status_str") == "error"
        status.dig(prompt_id, "status", "messages").each do |message|
          raise "Image generation failed: #{message.dig(1, "exception_message")}" if message[0] == "execution_error"
        end
        raise "Image generation failed"
      elsif status&.dig(prompt_id, "status", "status_str") == "success"
        if outputs = status.dig(prompt_id, "outputs", params[:output], "images")
          image_info = outputs.first
          image_data = get_image(image_info["filename"], image_info["subfolder"], image_info["type"])
          ws&.close
          return {
            image_data: image_data,
            filename: image_info["filename"],
            prompt_id: prompt_id
          }
        end
        raise "No images found in completed generation"
      end
      
      sleep(1) # Wait a second before checking again
    end
  end
end
