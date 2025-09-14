#!/bin/bash

curl --request POST \
  --url https://image.chutes.ai/generate \
  --header 'Authorization: Bearer ${CHUTE_TOKEN}' \
  --header 'Content-Type: application/json' \
  --data '{
    "model": "qwen-image",
    "prompt": "A beautiful sunset over mountains",
    "negative_prompt": "blur, distortion, low quality",
    "true_cfg_scale": 4.0,
    "width": 1024,
    "height": 1024,
    "num_inference_steps": 50,
    "seed": 1
}' -o output1.jpg


curl --request POST \
  --url https://image.chutes.ai/generate \
  --header 'Authorization: Bearer ${CHUTE_TOKEN}' \
  --header 'Content-Type: application/json' \
  --data '{
    "model": "FLUX.1-schnell",
    "prompt": "A beautiful sunset over mountains",
    "guidance_scale": 7.5,
    "width": 1024,
    "height": 1024,
    "num_inference_steps": 50,
    "seed": 1
}' -o output2.jpg

