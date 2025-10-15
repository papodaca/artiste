class HelpCommand < BaseCommand
  def help_text
    <<~HELP
      Available parameters:
        --ar|-a <ratio>        Set aspect ratio (e.g., 3:2, 16:9, 1:1)
        --basesize|-b <pixels> Set base size for aspect ratio calculations
        --height|-h <pixels>   Set image height
        --model|-m <name>      Set model (flux, qwen)
        --no|-n                Set the negative prompt
        --preset|-P <name>     Apply preset parameters and append preset prompt
        --<preset_name>        Apply preset directly by name (e.g., --vibrant_colors)
        --private|-p           Generate images that are not publicly shared
        --shift|-S <number>    Set shift parameter (for qwen model)
        --steps|-s <number>    Set number of generation steps, more steps more better
        --width|-w <pixels>    Set image width

      Example: "a beautiful sunset --ar 16:9 --steps 20 --private"
      
      Available commands:
      
      /generate <prompt> [options] - Generate an image based on your prompt
        Options (same parameters as image generation)
        Example: /generate a beautiful sunset --ar 16:9 --steps 20 --private
      
      /set_settings [options] - Set default settings for image generation
        Options (same parameters as image generation):
          --delete|-d <key>      Delete a setting (e.g., --delete aspect_ratio)
        
        Examples:
          /set_settings --ar 3:2 --steps 30
          /set_settings --delete aspect_ratio
      
      /get_settings - Display current default settings
      
      /details <image_name|prompt_id> - Show generation details for a specific image
        Example: /details output_20241230_123456.png

      /text <text prompt> [options]
        Options:
          --model|-m <name>       Set model (qwen, qwen-coder, llama, glm-4, glm-4.5, deepseek-r1, deepseek-v3 and gpt-oss)
          --temperature|-t <temp> Set temperature (default: 0.7)
          --no-system             Disable Artiste's system prompt
      
      /edit <prompt> [options] - Edit an image based on your prompt
        Options:
          --image|-i <url|filename> Specify image URL or filename to edit
          --task|-t <id>            Specify task ID of previously generated image to edit
          --ar|-a <ratio>           Set aspect ratio (e.g., 3:2, 16:9, 1:1)
          --basesize|-b <pixels>    Set base size for aspect ratio calculations
          --height|-h <pixels>      Set image height
          --preset|-P <name>        Apply preset parameters and append preset prompt
          --<preset_name>           Apply preset directly by name (e.g., --vibrant_colors)
          --private|-p              Generate images that are not publicly shared
          --shift|-S <number>       Set shift parameter (for qwen model)
          --steps|-s <number>       Set number of generation steps, more steps more better
          --width|-w <pixels>      Set image width
        
        You can provide images in multiple ways:
          - Attach images directly to your message
          - Use --image with a URL (e.g., --image https://example.com/image.png)
          - Use --image with a filename, for previous gen (e.g., --image output_20241230_123456.png)
          - Use --task with a task ID (e.g., --task 12345)
        
        Example: /edit make this image more vibrant --image output_20241230_123456.png --steps 20
      
      /video <prompt> [options] - Generate a video based on your prompt or from an image
        Options:
          --frames|-f <number>     Set number of frames (default: 81)
          --guidance|-g <number>   Set guidance scale (default: 5.0)
          --ar|-a <ratio>          Set aspect ratio (e.g., 3:2, 16:9, 1:1)
          --no|-n                  Set the negative prompt
          --preset|-P <name>       Apply preset parameters and append preset prompt
          --<preset_name>          Apply preset directly by name (e.g., --vibrant_colors)
          --private|-p             Generate videos that are not publicly shared
          --steps|-s <number>      Set number of generation steps
          --seed <number>          Set seed for reproducible generation
          --image|-i <url|filename> Specify image URL or filename to convert to video
          --task|-t <id>            Specify task ID of previously generated image to convert to video
        
        You can provide images in multiple ways:
          - Attach images directly to your message
          - Use --image with a URL (e.g., --image https://example.com/image.png)
          - Use --image with a filename, for previous gen (e.g., --image output_20241230_123456.png)
          - Use --task with a task ID (e.g., --task 12345)
        
        Note: Only one image can be used for video generation at a time.
        
        Examples:
          /video a beautiful sunset --ar 16:9 --frames 120 --guidance 7.0
          /video make this image animated --image output_20241230_123456.png
          /video add motion to this scene --task 12345
      
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
