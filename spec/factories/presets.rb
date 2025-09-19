FactoryBot.define do
  factory :preset do
    name { "test_preset" }
    user_id { "test_user" }
    username { "test_user" }
    prompt { "test prompt" }
    parameters { {steps: 20, model: "flux"}.to_json }

    skip_create
    initialize_with { new(attributes).tap { |p| p.save } }

    trait :landscape do
      name { "landscape_preset" }
      prompt { "beautiful mountain landscape with trees" }
      parameters { {steps: 30, aspect_ratio: "16:9", model: "flux"}.to_json }
    end

    trait :params_only do
      name { "params_only_preset" }
      prompt { "" }
      parameters { {steps: 40, width: 800, height: 600}.to_json }
    end

    trait :vibrant_colors do
      name { "vibrant_colors" }
      prompt { "vibrant and colorful style" }
      parameters { {steps: 25, model: "flux"}.to_json }
    end

    trait :high_quality do
      name { "high_quality" }
      prompt { "high quality, detailed" }
      parameters { {steps: 50}.to_json }
    end

    trait :realistic do
      name { "realistic" }
      prompt { "photorealistic, detailed" }
      parameters { {steps: 40, model: "flux"}.to_json }
    end

    trait :colorful do
      name { "colorful" }
      prompt { "vibrant colors, saturated" }
      parameters { {steps: 30, width: 800}.to_json }
    end

    trait :anime do
      name { "anime" }
      prompt { "anime style, cel-shaded" }
      parameters { {steps: 35, model: "qwen"}.to_json }
    end

    trait :photorealistic do
      name { "photorealistic" }
      prompt { "photorealistic, detailed" }
      parameters { {steps: 40, model: "flux"}.to_json }
    end
  end
end
