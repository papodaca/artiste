# Artiste

A bot to reply in mattermost with an image from [Comfy UI](https://github.com/comfyanonymous/ComfyUI)!

## Flags

| Flag         | Description                                      | Example             | Notes                                                                  |
| ------------ | ------------------------------------------------ | ------------------- | ---------------------------------------------------------------------- |
| `--ar <W:H>` | Aspect ratio in `width:height` format.           | `--ar 16:9`         | Overrides default width/height. Uses nearest multiple of 8 for output. |
| `--basesize N` | The base size of the image to be used with the aspect ratio.           | `--basesize 1024`         | Overrides default of 1024. Uses nearest multiple of 8 for output. |
| `--width N`  | Explicit image width in pixels.                  | `--width 640`       | Overrides aspect ratio width if also specified.                        |
| `--height N` | Explicit image height in pixels.                 | `--height 768`      | Overrides aspect ratio height if also specified.                       |
| `--steps N`  | Number of generation steps (default `2`).        | `--steps 30`        |                                                                        |
| `--seed N`   | Random seed (default = random 32-bit int).       | `--seed 12345`      | Use fixed seed for reproducibility.                                    |

If no parameters are provided, defaults are:

* **width**: `1024`
* **height**: `1024`
* **steps**: `2`
* **seed**: random number

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
