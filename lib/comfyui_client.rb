require "fileutils"

class ComfyuiClient
  include HTTParty

  DEFAULT ={
    flux: {
      width: 1024,
      height: 1024,
      steps: 2
    },
    qwen: {
      steps: 50,
      width: 1328,
      height: 1328,
      shift: 3.1,
    },
  }

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

  # Load workflow template from JSON file
  def load_workflow_template(workflow_path)
    if File.exist?(workflow_path)
      JSON.parse(File.read(workflow_path))
    else
      raise "Workflow file not found: #{workflow_path}"
    end
  end

  # Convert aspect ratio to width and height
  def aspect_ratio_to_dimensions(aspect_ratio, base_size = 1024)
    aspect_ratios = {
      # Standard ratios
      "1:1" => [1024, 1024],
      "4:3" => [1152, 864],
      "3:2" => [1216, 810],
      "16:10" => [1280, 800],
      "5:4" => [1024, 819],
      "3:4" => [864, 1152],
      "2:3" => [810, 1216],
      "10:16" => [800, 1280],
      "4:5" => [819, 1024],
      
      # Widescreen ratios
      "16:9" => [1344, 768],
      "21:9" => [1536, 658],
      "32:9" => [1792, 512],
      
      # Portrait versions
      "9:16" => [768, 1344],
      "9:21" => [658, 1536],
      "9:32" => [512, 1792],
      
      # Cinema ratios
      "2.35:1" => [1472, 626],
      "2.4:1" => [1536, 640],
      "1:2.35" => [626, 1472],
      "1:2.4" => [640, 1536]
    }
    
    if aspect_ratios.key?(aspect_ratio) && base_size == 1024
      aspect_ratios[aspect_ratio]
    else
      # Try to parse custom ratios like "16:9"
      if match = aspect_ratio.match(/^(\d+(?:\.\d+)?):(\d+(?:\.\d+)?)$/)
        w_ratio = match[1].to_f
        h_ratio = match[2].to_f
        
        # Calculate dimensions maintaining aspect ratio with base_size as reference
        if w_ratio >= h_ratio
          width = base_size
          height = (base_size * h_ratio / w_ratio).round
        else
          height = base_size
          width = (base_size * w_ratio / h_ratio).round
        end
        
        # Make sure dimensions are multiples of 8 (common requirement for AI models)
        width = (width / 8).round * 8
        height = (height / 8).round * 8
        
        [width, height]
      else
        [1024, 1024] # Default fallback
      end
    end
  end

  # Parse parameters from prompt text
  def parse_prompt_parameters(full_prompt)
    # Extract parameters using regex
    params = {
      model: "flux",
      seed: rand(1000000000),
      negative_prompt: "",
    }.merge(DEFAULT[:flux])
    
    # Remove parameters from prompt and store clean prompt
    clean_prompt = full_prompt.dup

    if match = full_prompt.match(/--model\s+(\w+)/)
      params[:model] = match[1].to_s
      default_params = DEFAULT[params[:model].to_sym]
      params.merge!(default_params) if !default_params.nil?
      clean_prompt.gsub!(/--model\s+(\w+)/, "")
    end

    basesize = 1024
    if match = full_prompt.match(/--basesize\s+(\d+)/)
      basesize = match[1].to_i
      clean_prompt.gsub!(/--basesize\s+\d+/, "")
    end
    
    # Extract aspect ratio first (this may override width/height)
    if match = full_prompt.match(/--ar\s+([^\s-]+)/)
      params[:aspect_ratio] = match[1]
      width, height = aspect_ratio_to_dimensions(params[:aspect_ratio], basesize)
      params[:width] = width
      params[:height] = height
      clean_prompt.gsub!(/--ar\s+[^\s-]+/, "")
    end

    if match = full_prompt.match(/--shift\s+(\d+.?\d*)/)
      params[:shift] = match[1].to_f
      clean_prompt.gsub!(/--shift\s+(\d+.?\d*)/, "")
    end
    
    # Extract width (this will override aspect ratio width if specified)
    if match = full_prompt.match(/--width\s+(\d+)/)
      params[:width] = match[1].to_i
      clean_prompt.gsub!(/--width\s+\d+/, "")
    end
    
    # Extract height (this will override aspect ratio height if specified)
    if match = full_prompt.match(/--height\s+(\d+)/)
      params[:height] = match[1].to_i
      clean_prompt.gsub!(/--height\s+\d+/, "")
    end
    
    # Extract steps
    if match = full_prompt.match(/--steps\s+(\d+)/)
      params[:steps] = match[1].to_i
      clean_prompt.gsub!(/--steps\s+\d+/, "")
    end
    
    # Extract seed
    if match = full_prompt.match(/--seed\s+(\d+)/)
      params[:seed] = match[1].to_i
      clean_prompt.gsub!(/--seed\s+\d+/, "")
    end
    
    # Extract negative prompt
    if match = full_prompt.match(/--no\s+([^-]+)(?=\s*(?:--|$))/)
      params[:negative_prompt] = match[1].strip
      clean_prompt.gsub!(/--no\s+[^-]+(?=\s*(?:--|$))/, "")
    end
    
    # Clean up extra whitespace
    clean_prompt = clean_prompt.gsub(/\s+/, " ").strip
    
    params.merge({
      prompt: clean_prompt
    })
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

  # Create workflow with automatic parameter parsing from prompt
  def create_workflow_with_parsed_params(full_prompt)
    parsed = parse_prompt_parameters(full_prompt)
    
    workflow, output = create_workflow_from_template(parsed[:model], parsed)
    [workflow, parsed.merge({output: output})]
  end

  # Poll for completion and return the generated image with parameter parsing
  def generate_and_wait(full_prompt, max_wait_seconds = 500)
    workflow, params = create_workflow_with_parsed_params(full_prompt)
    result = queue_prompt(workflow)
    prompt_id = result["prompt_id"]
    
    if prompt_id.nil?
      raise "Failed to get prompt ID from ComfyUI response: #{result}"
    end
    
    start_time = Time.now
    
    loop do
      if Time.now - start_time > max_wait_seconds
        raise "Image generation timed out after #{max_wait_seconds} seconds"
      end
      
      status = get_prompt_status(prompt_id)
      
      if status && status[prompt_id] && status[prompt_id]["status"] && status[prompt_id]["status"]["completed"]
        raise "Image generation didn't complete successfully" if status[prompt_id]["status"]["status_str"] != "success"
        
        # Get the output images
        output_id = params[:output]
        outputs = status[prompt_id]["outputs"]
        if outputs && outputs[output_id] && outputs[output_id]["images"]
          image_info = outputs[output_id]["images"].first
          if image_info
            image_data = get_image(image_info["filename"], image_info["subfolder"], image_info["type"])
            return {
              image_data: image_data,
              filename: image_info["filename"],
              prompt_id: prompt_id
            }
          end
        end
        raise "No images found in completed generation"
      end
      
      sleep(2) # Wait 2 seconds before checking again
    end
  end
end
