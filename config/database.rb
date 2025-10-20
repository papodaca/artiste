DB_PATH = File.expand_path((ENV["RACK_ENV"] == "test") ? "../db/artiste_test.db" : "../db/artiste.db", __dir__)
FileUtils.mkdir_p(File.dirname(DB_PATH))
DB = Sequel.sqlite(DB_PATH)

# Migration: Rename comfyui_prompt_id to prompt_id if the column exists
if DB.table_exists?(:generation_tasks) 
  if DB[:generation_tasks].columns.include?(:comfyui_prompt_id)
    DB.alter_table(:generation_tasks) do
      rename_column :comfyui_prompt_id, :prompt_id
    end
  end

  if !DB[:generation_tasks].columns.include?(:deleted_at)
    DB.add_column :generation_tasks, :deleted_at, DateTime
  end
end

# Create user_settings table if it doesn't exist
DB.create_table? :user_settings do
  primary_key :id
  String :user_id, null: false, unique: true
  String :username
  Text :params, default: "{}"
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
end

DB.create_table? :generation_tasks do
  primary_key :id
  String :user_id, null: false
  String :username
  String :status, default: "pending" # pending, processing, completed, failed
  Text :prompt, null: false
  Text :parameters # JSON string of generation parameters
  Text :exif_data, default: "{}" # JSON string of EXIF data
  String :workflow_type # flux, qwen, etc.
  String :prompt_id # Prompt ID for tracking
  String :output_filename
  Text :error_message # Error details if generation fails
  TrueClass :private, default: false # Flag for private images
  DateTime :queued_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :started_at
  DateTime :completed_at
  Float :processing_time_seconds
  DateTime :deleted_at # Soft delete timestamp

  index :user_id
  index :status
  index [:user_id, :status]
  index :queued_at
  index :deleted_at
end

DB.create_table? :presets do
  primary_key :id
  String :name, null: false, unique: true
  String :user_id, null: false
  String :username
  Text :prompt, null: false
  Text :parameters, default: "{}" # JSON string of parameters
  String :example_image # URL to example image
  DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
  DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

  index :user_id
  index :name
end

# User Settings model
class UserSettings < Sequel::Model(:user_settings)
  def before_update
    self.updated_at = Time.now
    super
  end

  def parsed_prompt_params
    JSON.parse(params, symbolize_names: true)
  rescue
    {}
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
    settings = find(user_id: user_id)

    settings ||= create(
      user_id: user_id,
      username: username
    )

    settings
  end
end

# Generation Tasks model
class GenerationTask < Sequel::Model(:generation_tasks)
  def parsed_parameters
    JSON.parse(parameters || "{}", symbolize_names: true)
  rescue
    {}
  end

  def set_parameters(params_hash)
    self.parameters = params_hash.to_json
  end

  def parsed_exif_data
    JSON.parse(exif_data || "{}", symbolize_names: true)
  rescue
    {}
  end

  def file_path
    target_dir = File.join(
      "db",
      "photos",
      completed_at.strftime("%Y"),
      completed_at.strftime("%m"),
      completed_at.strftime("%d")
    )
    FileUtils.mkdir_p(target_dir)
    target_dir
  end

  def set_exif_data(exif_hash)
    self.exif_data = exif_hash.to_json
    save
  end

  def mark_processing(prompt_id = nil)
    self.status = "processing"
    self.started_at = Time.now
    self.prompt_id = prompt_id if prompt_id.present?
    save
  end

  def mark_completed(output_filename = nil, prompt_id = nil)
    self.status = "completed"
    self.completed_at = Time.now
    self.output_filename = output_filename if output_filename
    self.prompt_id = prompt_id if prompt_id.present?
    if started_at
      self.processing_time_seconds = (Time.now - started_at).to_f
    end
    save
  end

  def mark_failed(error_message)
    self.status = "failed"
    self.completed_at = Time.now
    self.error_message = error_message
    if started_at
      self.processing_time_seconds = (Time.now - started_at).to_f
    end
    save
  end

  def to_h
    {
      id: id,
      output_filename: output_filename,
      username: username,
      user_id: user_id,
      workflow_type: workflow_type,
      completed_at: completed_at&.strftime("%Y-%m-%d %H:%M:%S"),
      private: send(:private),
      prompt: prompt
    }
  end

  # Soft delete methods
  def soft_delete
    self.deleted_at = Time.now
    save
  end

  def deleted?
    !deleted_at.nil?
  end

  # Class methods for querying with soft delete consideration
  def self.not_deleted
    where(deleted_at: nil)
  end

  def self.deleted
    where(Sequel.~(deleted_at: nil))
  end

  # Class methods for querying (excluding deleted records by default)
  def self.for_user(user_id)
    not_deleted.where(user_id: user_id).order(:queued_at)
  end

  def self.pending
    not_deleted.where(status: "pending").order(:queued_at)
  end

  def self.processing
    not_deleted.where(status: "processing").order(:started_at)
  end

  def self.completed
    not_deleted.where(status: "completed").order(:completed_at)
  end

  def self.failed
    not_deleted.where(status: "failed").order(:completed_at)
  end

  def self.pub
    completed.where(private: false)
  end

  def self.completed
    not_deleted.where(status: "completed")
  end
end

class Preset < Sequel::Model(:presets)
  def before_update
    self.updated_at = Time.now
    super
  end

  def parsed_parameters
    JSON.parse(parameters, symbolize_names: true)
  rescue
    {}
  end

  def set_parameters(params_hash)
    self.parameters = params_hash.to_json
  end

  # Class methods for querying
  def self.for_user(user_id)
    where(user_id: user_id).order(:name)
  end

  def self.find_by_name(name)
    where(name: name).first
  end
end
