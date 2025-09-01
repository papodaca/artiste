# Artiste

A bot to reply in mattermost with an image from [Comfy UI](https://github.com/comfyanonymous/ComfyUI)!

## Commands

Artiste supports slash commands for configuration and information:

### `/set_settings [options]`
Set default settings for image generation.

**Options:**
- `--ar <ratio>` - Set aspect ratio (e.g., 3:2, 16:9, 1:1)
- `--width <pixels>` - Set image width
- `--height <pixels>` - Set image height  
- `--steps <number>` - Set number of generation steps
- `--model <name>` - Set default model (flux, qwen)
- `--shift <number>` - Set shift parameter (for qwen model)
- `--basesize <pixels>` - Set base size for aspect ratio calculations
- `--delete <key>` - Delete a setting (e.g., --delete aspect_ratio)

**Examples:**
```
/set_settings --ar 3:2 --steps 30
/set_settings --delete aspect_ratio
```

### `/get_settings`
Display current default settings.

### `/details <image_name|comfyui_prompt_id>`
Show generation details for a specific image.

**Example:**
```
/details output_20241230_123456.png
```

### `/help`
Show help message with all available commands and parameters.

## Image Generation Parameters

For image generation, use normal prompts with optional parameters:

| Parameter | Description | Example | Notes |
| --------- | ----------- | ------- | ----- |
| `--ar <W:H>` | Aspect ratio in `width:height` format | `--ar 16:9` | Overrides default width/height. Uses nearest multiple of 8 for output |
| `--basesize N` | Base size for aspect ratio calculations | `--basesize 1024` | Default is 1024. Uses nearest multiple of 8 for output |
| `--width N` | Explicit image width in pixels | `--width 640` | Overrides aspect ratio width if also specified |
| `--height N` | Explicit image height in pixels | `--height 768` | Overrides aspect ratio height if also specified |
| `--steps N` | Number of generation steps | `--steps 30` | Default varies by model (flux: 2, qwen: 20) |
| `--seed N` | Random seed for reproducibility | `--seed 12345` | Default is random number |
| `--model <name>` | AI model to use | `--model qwen` | Available: flux, qwen |
| `--shift <number>` | Shift parameter (qwen model) | `--shift 3.1` | Default: 3.1 for qwen |
| `--no <text>` | Negative prompt | `--no blurry, dark` | Things to avoid in the image |

**Example:**
```
a beautiful sunset --ar 16:9 --steps 20
```

## Default Settings

### Flux Model Defaults:
- **width**: `1024`
- **height**: `1024`
- **steps**: `2`

### Qwen Model Defaults:
- **width**: `1328`
- **height**: `1328`  
- **steps**: `20`
- **shift**: `3.1`

All models use a random seed by default.

---

## Supported Aspect Ratios

The following aspect ratios are predefined. If not listed, custom ratios like `7:3` are also supported (dimensions will be scaled to the nearest multiple of 8 with `base_size = 1024`).

| Ratio          | Width × Height |
| -------------- | -------------- |
| **Standard**   |                |
| `1:1`          | `1024 × 1024`  |
| `4:3`          | `1152 × 864`   |
| `3:2`          | `1216 × 810`   |
| `16:10`        | `1280 × 800`   |
| `5:4`          | `1024 × 819`   |
| `3:4`          | `864 × 1152`   |
| `2:3`          | `810 × 1216`   |
| `10:16`        | `800 × 1280`   |
| `4:5`          | `819 × 1024`   |
| **Widescreen** |                |
| `16:9`         | `1344 × 768`   |
| `21:9`         | `1536 × 658`   |
| `32:9`         | `1792 × 512`   |
| **Portrait**   |                |
| `9:16`         | `768 × 1344`   |
| `9:21`         | `658 × 1536`   |
| `9:32`         | `512 × 1792`   |
| **Cinema**     |                |
| `2.35:1`       | `1472 × 626`   |
| `2.4:1`        | `1536 × 640`   |
| `1:2.35`       | `626 × 1472`   |
| `1:2.4`        | `640 × 1536`   |

## Running with Docker

Artiste can be run using Docker for easy deployment.

### Prerequisites

- Docker and Docker Compose installed on your system
- A running ComfyUI instance (accessible from the Docker container)
- Mattermost server configuration

### Using Docker Compose

The easiet way to deploy is by adding to mattermost's `docker-compose.yml`

1. **Add artiste service:**
   ```yaml
    artiste:
      image: ghcr.io/papodaca/artiste:main
      restart: always
      ports:
        - 4567:4567
      volumes:
        - ./artiste_db:/app/db
      environment:
        MATTERMOST_URL: http://app:8000
        MATTERMOST_TOKEN: <token>
        MATTERMOST_CHANNELS: <channel1>,<channel2>
        COMFYUI_URL: http://comfyui:8188
        COMFYUI_TOKEN: <token> # needed if you are using comfyui-login
   ```

2. **Start:**
   ```bash
   docker-compose up -d artiste
   ```

### Using Docker Only

If you have an existing Mattermost server and just want to run Artiste:

```bash
docker run -d --name artiste \
  --env-file .env \
  -v $(pwd)/db:/app/db \
  ghcr.io/papodaca/artiste:main
```

### Environment Variables

Make sure your `.env` file includes:
- Mattermost server connection details
- ComfyUI server URL and settings
- Database configuration (if using external database)

### Volumes

The Docker setup uses the following volumes:
- `./db:/app/workdbflows` - Artiste's database dir
