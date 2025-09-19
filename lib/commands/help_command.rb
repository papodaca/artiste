class HelpCommand < BaseCommand
  def help_text
    <<~HELP
      Available parameters:
        --ar|-a <ratio>        Set aspect ratio (e.g., 3:2, 16:9, 1:1)
        --basesize|-b <pixels> Set base size for aspect ratio calculations
        --height|-h <pixels>   Set image height
        --model|-m <name>      Set model (flux, qwen)
        --preset|-P <name>     Apply preset parameters and append preset prompt
        --<preset_name>        Apply preset directly by name (e.g., --vibrant_colors)
        --private|-p           Generate images that are not publicly shared
        --shift|-S <number>    Set shift parameter (for qwen model)
        --steps|-s <number>    Set number of generation steps, more steps more better
        --width|-w <pixels>    Set image width

      Example: "a beautiful sunset --ar 16:9 --steps 20 --private"
      
      Available commands:
      
      /set_settings [options] - Set default settings for image generation
        Options (same parameters as image generation):
          --delete|-d <key>      Delete a setting (e.g., --delete aspect_ratio)
        
        Examples: 
          /set_settings --ar 3:2 --steps 30
          /set_settings --delete aspect_ratio
      
      /get_settings - Display current default settings
      
      /details <image_name|comfyui_prompt_id> - Show generation details for a specific image
        Example: /details output_20241230_123456.png

      /text <text prompt> [options]
        Options:
          --model|-m <name>       Set model (qwen, qwen-coder, llama, glm-4, glm-4.5, deepseek-r1, deepseek-v3 and gpt-oss)
          --temperature|-t <temp> Set temperature (default: 0.7)
          --no-system             Disable Artiste's system prompt
      
      /help - Show this help message
      
      Preset management commands:
      /create_preset <name> <prompt> [options] - Create a new preset with prompt and parameters
      /list_presets - List all available presets
      /show_preset <name> - Show details of a specific preset
      /update_preset <name> <prompt> [options] - Update a preset (creator-only)
      /delete_preset <name> - Delete a preset (creator-only)
      
      Example: "landscape photo --preset vibrant_colors"
    HELP
  end

  def execute
    debug_log("Handling help command")
    server.respond(message, help_text)
  end
end
