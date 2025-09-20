require "fileutils"
require "base64"

MODEL_MAP = {
  "flux" => "FLUX.1-schnell",
  "qwen-image" => "qwen-image",
  "qwen-image-edit" => "qwen-image-edit"
}

class ChutesClient < ImageGenerationClient
  attr_reader :http_client

  def initialize(token = nil)
    @http_client = ChutesHttpClient.new("https://image.chutes.ai", token)
  end

  # Generate image using qwen-image model
  def generate_qwen_image(params, &block)
    # Set default values for parameters
    payload = {
      "model" => "qwen-image",
      "prompt" => params[:prompt] || "",
      "negative_prompt" => params[:negative_prompt] || "",
      "guidance_scale" => params[:shift] || 4.0,
      "width" => params[:width] || 1024,
      "height" => params[:height] || 1024,
      "num_inference_steps" => params[:steps] || 50,
      "seed" => params[:seed] || 1
    }

    block.call(:started, nil, nil) if block_given?

    # Generate the image
    result = http_client.generate_image(payload)
    image_data = result[:image_data]
    prompt_id = result[:prompt_id]

    # Convert to PNG if needed
    png_data = convert_to_png(image_data)

    block.call(:completed, prompt_id, nil) if block_given?

    {
      image_data: png_data,
      prompt_id: prompt_id
    }
  end

  # Generate image using FLUX.1-schnell model
  def generate_flux_image(params, &block)
    # Set default values for parameters
    payload = {
      "model" => "FLUX.1-schnell",
      "prompt" => params[:prompt] || "",
      "guidance_scale" => params[:shuft] || 7.5,
      "width" => params[:width] || 1024,
      "height" => params[:height] || 1024,
      "num_inference_steps" => params[:steps] || 10,
      "seed" => params[:seed] || 1
    }

    block.call(:started, nil, nil) if block_given?

    # Generate the image
    result = http_client.generate_image(payload)
    image_data = result[:image_data]
    prompt_id = result[:prompt_id]

    # Convert to PNG if needed
    png_data = convert_to_png(image_data)

    block.call(:completed, prompt_id, nil) if block_given?

    {
      image_data: png_data,
      prompt_id: prompt_id
    }
  end

  # Generate image using qwen-image-edit model for image editing
  def generate_qwen_image_edit(params, &block)
    # Set default values for parameters
    payload = {
      "prompt" => params[:prompt] || "",
      "negative_prompt" => params[:negative_prompt] || "",
      "true_cfg_scale" => params[:shift] || 4.0,
      "width" => params[:width] || 1024,
      "height" => params[:height] || 1024,
      "num_inference_steps" => params[:steps] || 50,
      "seed" => params[:seed] || 1,
      "image_b64" => params[:image_b64] || ""
    }

    block.call(:started, nil, nil) if block_given?

    # Generate the image using the edit endpoint
    result = http_client.generate_image_edit(payload)
    image_data = result[:image_data]
    prompt_id = result[:prompt_id]

    png_data = convert_to_png(image_data)

    block.call(:completed, prompt_id, nil) if block_given?

    {
      image_data: png_data,
      prompt_id: prompt_id
    }
  end

  # Generic generate method that selects model based on params
  def generate(params, &block)
    model = params[:model] || "qwen-image"

    case model
    when "qwen", "qwen-image"
      generate_qwen_image(params, &block)
    when "flux"
      generate_flux_image(params, &block)
    when "qwen-image-edit"
      generate_qwen_image_edit(params, &block)
    else
      raise "Unsupported model: #{model}. Supported models are: qwen-image, FLUX.1-schnell, qwen-image-edit"
    end
  end

  private

  # Convert image data to PNG format using mini_magick
  def convert_to_png(image_data)
    # Create a temporary file with the image data
    temp_file = Tempfile.new(["image", ".tmp"])
    temp_file.binmode
    temp_file.write(image_data)
    temp_file.flush

    begin
      # Use mini_magick to convert to PNG
      image = MiniMagick::Image.open(temp_file.path)
      image.format "png"

      # Get the PNG data
      png_data = image.to_blob
      png_data
    ensure
      # Clean up the temporary file
      temp_file.close
      temp_file.unlink
    end
  end
end
