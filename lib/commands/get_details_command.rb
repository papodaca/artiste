class GetDetailsCommand < BaseCommand
  def self.parse(image_name)
    {
      image_name: image_name.strip
    }
  end

  def execute
    debug("Handling get details command")
    image_name = parsed_result[:image_name]
    debug("Looking up details for image: #{image_name}")

    # Look up generation task by output filename
    task = GenerationTask.where(output_filename: image_name).first || GenerationTask.where(prompt_id: image_name).first

    if task.nil?
      debug("No generation task found for image: #{image_name}")
      server.respond(message, "❌ No generation details found for image: `#{image_name}`\n\nMake sure you're using the exact filename as it appears in the generated image.")
      return
    end

    debug("Found generation task ##{task.id} for image: #{image_name}")

    # Try to read EXIF data from the actual image file
    exif_data = task.parsed_exif_data

    # Build detailed response
    details_text = []
    details_text << "🖼️ **Generation Details for:** `#{image_name}`"
    details_text << ""

    unless exif_data.empty?
      details_text << "**Image Metadata (EXIF):**"
      exif_data.each do |key, value|
        details_text << "• #{key.to_s.titleize}: #{value}"
      end
      details_text << ""
    end

    details_text << "**Database Info:**"
    details_text << "• Task ID: ##{task.id}"
    details_text << "• User: #{task.username} (#{task.user_id})"
    details_text << "• Status: #{task.status.upcase}"
    details_text << "• Workflow: #{task.workflow_type || "N/A"}"
    details_text << ""

    # Timing information
    details_text << "**Timing:**"
    details_text << "• Queued: #{task.queued_at.strftime("%Y-%m-%d %H:%M:%S UTC") if task.queued_at}"
    details_text << "• Started: #{task.started_at.strftime("%Y-%m-%d %H:%M:%S UTC") if task.started_at}"
    details_text << "• Completed: #{task.completed_at.strftime("%Y-%m-%d %H:%M:%S UTC") if task.completed_at}"
    if task.processing_time_seconds
      details_text << "• Processing Time: #{"%.2f" % task.processing_time_seconds}s"
    end
    details_text << ""

    # Original prompt
    details_text << "**Original Prompt:**"
    details_text << "```"
    details_text << task.prompt
    details_text << "```"
    details_text << ""

    # Generation parameters
    if task.parameters && !task.parameters.empty?
      params = task.parsed_parameters
      details_text << "**Generation Parameters:**"
      details_text << "```json"
      details_text << JSON.pretty_generate(params)
      details_text << "```"
      details_text << ""
    end

    # Prompt details
    if task.prompt_id
      details_text << "**Info:**"
      details_text << "• Prompt ID: #{task.prompt_id}"
      details_text << ""
    end

    # Error information if failed
    if task.status == "failed" && task.error_message
      details_text << "**Error Details:**"
      details_text << "```"
      details_text << task.error_message
      details_text << "```"
    end

    server.respond(message, details_text.join("\n"))
  end
end
