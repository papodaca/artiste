require 'sequel'
require 'fileutils'

# Database configuration
DB_PATH = File.expand_path("../db/artiste.db", __dir__)

# Ensure db directory exists
FileUtils.mkdir_p(File.dirname(DB_PATH))

# Connect to SQLite database
DB = Sequel.sqlite(DB_PATH)

# Create user_settings table if it doesn't exist
DB.create_table? :user_settings do
  primary_key :id
  String :user_id, null: false, unique: true
  String :username
  Text :params, default: '{}'
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

# Create generation_tasks table if it doesn't exist
DB.create_table? :generation_tasks do
  primary_key :id
  String :user_id, null: false
  String :username
  String :status, default: 'pending' # pending, processing, completed, failed
  Text :prompt, null: false
  Text :parameters # JSON string of generation parameters
  Text :exif_data, default: '{}' # JSON string of EXIF data
  String :workflow_type # flux, qwen, etc.
  String :comfyui_prompt_id # ComfyUI's prompt ID for tracking
  String :output_filename
  Text :error_message # Error details if generation fails
  TrueClass :private, default: false # Flag for private images
  DateTime :queued_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :started_at
  DateTime :completed_at
  Float :processing_time_seconds
  
  index :user_id
  index :status
  index [:user_id, :status]
  index :queued_at
end

begin
  unless DB.schema(:generation_tasks).any? { |column, info| column == :private }
    puts "Adding generation_task private column"
    DB.alter_table(:generation_tasks) do
      add_column(:private, TrueClass, default: false)
    end
  end
rescue => e
  puts "Warning: Could not check/add private column: #{e.message}"
end

begin
  unless DB.schema(:generation_tasks).any? { |column, info| column == :exif_data }
    puts "Adding generation_task exif_data column"
    DB.alter_table(:generation_tasks) do
      add_column(:exif_data, Text, default: '{}')
    end
  end
rescue => e
  puts "Warning: Could not check/add exif_data column: #{e.message}"
end

# User Settings model
class UserSettings < Sequel::Model(:user_settings)
  def before_update
    self.updated_at = Time.now
    super
  end
  
  def parsed_prompt_params
    JSON.parse(self.params, symbolize_names: true) rescue {}
  end
  
  def update_prompt_params(params_hash)
    self.params = params_hash.to_json
  end

  def set_param(key, value) 
    params = parsed_prompt_params
    params[key] = value
    self.params = params.to_json
    value
  end

  def delete_param(key)
    params = parsed_prompt_params
    if params.has_key?(key)
      params.delete(key)
      self.params = params.to_json
      return true
    end
    false
  end
  
  # Get user settings or create default ones
  def self.get_or_create_for_user(user_id, username = nil)
    settings = self.find(user_id: user_id)
    
    unless settings
      settings = self.create(
        user_id: user_id,
        username: username
      )
    end
    
    settings
  end
end

# Generation Tasks model
class GenerationTask < Sequel::Model(:generation_tasks)
  def parsed_parameters
    JSON.parse(self.parameters || '{}', symbolize_names: true) rescue {}
  end
  
  def set_parameters(params_hash)
    self.parameters = params_hash.to_json
  end
  
  def parsed_exif_data
    JSON.parse(self.exif_data || '{}', symbolize_names: true) rescue {}
  end

  def file_path
    target_dir = File.join(
      'db',
      'photos',
      self.completed_at.strftime('%Y'),
      self.completed_at.strftime('%m'),
      self.completed_at.strftime('%d')
    )
    FileUtils.mkdir_p(target_dir)
    target_dir
  end
  
  def set_exif_data(exif_hash)
    self.exif_data = exif_hash.to_json
    self.save
  end
  
  def mark_processing(comfyui_prompt_id = nil)
    self.status = 'processing'
    self.started_at = Time.now
    self.comfyui_prompt_id = comfyui_prompt_id if comfyui_prompt_id.present?
    self.save
  end
  
  def mark_completed(output_filename = nil, comfyui_prompt_id = nil)
    self.status = 'completed'
    self.completed_at = Time.now
    self.output_filename = output_filename if output_filename
    if self.started_at
      self.processing_time_seconds = (Time.now - self.started_at).to_f
    end
    self.save
  end
  
  def mark_failed(error_message)
    self.status = 'failed'
    self.completed_at = Time.now
    self.error_message = error_message
    if self.started_at
      self.processing_time_seconds = (Time.now - self.started_at).to_f
    end
    self.save
  end
  
  # Class methods for querying
  def self.for_user(user_id)
    where(user_id: user_id).order(:queued_at)
  end
  
  def self.pending
    where(status: 'pending').order(:queued_at)
  end
  
  def self.processing
    where(status: 'processing').order(:started_at)
  end
  
  def self.completed
    where(status: 'completed').order(:completed_at)
  end
  
  def self.failed
    where(status: 'failed').order(:completed_at)
  end

  def self.pub
    where(status: 'completed', private: false)
  end
end
