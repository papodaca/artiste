#!/usr/bin/env ruby

require "fileutils"
require_relative "../config/environment"
require_relative "../config/database"

class MissingImageDownloader
  def initialize
    @comfyui_url = ENV["COMFYUI_URL"]
    @comfyui_token = ENV["COMFYUI_TOKEN"]

    if @comfyui_url.nil? || @comfyui_url.empty?
      puts "Error: COMFYUI_URL environment variable is required"
      exit 1
    end

    @comfyui_client = ComfyuiClient.new(@comfyui_url, @comfyui_token)
    @downloaded_count = 0
    @skipped_count = 0
    @error_count = 0
  end

  def run
    puts "Starting missing image download check..."
    puts "ComfyUI URL: #{@comfyui_url}"

    # Find all completed generation tasks that have an output filename
    completed_tasks = GenerationTask.completed.where(Sequel.~(output_filename: nil))

    puts "Found #{completed_tasks.count} completed tasks to check"

    completed_tasks.each do |task|
      check_and_download_task_image(task)
    end

    puts "\n" + "=" * 60
    puts "Download Summary:"
    puts "  Downloaded: #{@downloaded_count}"
    puts "  Skipped (already exists): #{@skipped_count}"
    puts "  Errors: #{@error_count}"
    puts "=" * 60
  end

  private

  def check_and_download_task_image(task)
    return unless task.output_filename

    # Calculate expected file path
    expected_path = get_expected_file_path(task)

    if File.exist?(expected_path)
      puts "✓ Image exists: #{expected_path}"
      @skipped_count += 1
      return
    end

    puts "⬇ Missing image, downloading: #{expected_path}"

    begin
      # Download image from ComfyUI
      image_data = @comfyui_client.http_client.get_image(task.output_filename)

      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(expected_path))

      # Write image data to file
      File.binwrite(expected_path, image_data)

      puts "✓ Downloaded successfully: #{expected_path}"
      @downloaded_count += 1
    rescue => e
      puts "✗ Error downloading #{task.output_filename}: #{e.message}"
      @error_count += 1
    end
  end

  def get_expected_file_path(task)
    # Use the task's file_path method which creates the directory structure
    # and combines it with the output filename
    File.join(task.file_path, task.output_filename)
  end
end

# Run the script if called directly
if __FILE__ == $0
  begin
    downloader = MissingImageDownloader.new
    downloader.run
  rescue Interrupt
    puts "\nDownload interrupted by user"
    exit 1
  rescue => e
    puts "Fatal error: #{e.message}"
    puts e.backtrace
    exit 1
  end
end
