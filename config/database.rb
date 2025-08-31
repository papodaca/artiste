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

puts "Database initialized at: #{DB_PATH}"
