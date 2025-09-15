class HelpCommand < BaseCommand
  def help_text
    <<~HELP
      Available commands:
      
      /set_settings [options] - Set default settings for image generation
        Options:
          --ar <ratio>        Set aspect ratio (e.g., 3:2, 16:9, 1:1)
          --width <pixels>    Set image width
          --height <pixels>   Set image height  
          --steps <number>    Set number of generation steps, more steps more better
          --model <name>      Set default model (flux, qwen)
          --shift <number>    Set shift parameter (for qwen model)
          --basesize <pixels> Set base size for aspect ratio calculations
          --delete <key>      Delete a setting (e.g., --delete aspect_ratio)
        
        Examples: 
          /set_settings --ar 3:2 --steps 30
          /set_settings --delete aspect_ratio
      
      /get_settings - Display current default settings
      
      /details <image_name|comfyui_prompt_id> - Show generation details for a specific image
        Example: /details output_20241230_123456.png

      /text <text prompt> [options]
        Options:
          --model <name>       Set model (qwen, qwen-coder, llama, glm-4, glm-4.5, deepseek-r1, deepseek-v3 and gpt-oss)
          --temperature <temp> Set temperature (default: 0.7)
          --no-system          Disable Artiste's system prompt
      
      /help - Show this help message
      
      For image generation, use normal prompts with optional parameters:
        --private             Generate images that are not publicly shared
        Example: "a beautiful sunset --ar 16:9 --steps 20 --private"
    HELP
  end

  def execute
    debug_log("Handling help command")
    server.respond(message, help_text)
  end
end
