class UserAuth
  attr_reader :session, :user_info, :access_token

  def initialize(session = {})
    @session = session
    @user_info = session[:user_info] ? JSON.parse(session[:user_info]) : nil
    @access_token = session[:access_token]
  end

  # Check if user is authenticated
  def authenticated?
    !@user_info.nil? && !@access_token.nil?
  end

  # Authenticate user with OAuth data
  def self.authenticate(session, access_token_data, user_info)
    return false unless access_token_data && user_info

    # Store authentication data in session
    session[:access_token] = access_token_data[:access_token]
    session[:refresh_token] = access_token_data[:refresh_token]
    session[:token_expires_at] = access_token_data[:expires_at]
    session[:user_info] = user_info.to_json
    session[:authenticated_at] = Time.now.to_i

    # Get or create user settings
    user_settings = UserSettings.get_or_create_for_user(
      user_info["id"],
      user_info["username"]
    )

    # Update user settings with latest info
    user_settings.username = user_info["username"]
    user_settings.save

    true
  end

  # Clear authentication (logout)
  def self.logout(session)
    session.clear
  end

  # Get current user ID
  def user_id
    @user_info ? @user_info["id"] : nil
  end

  # Get current username
  def username
    @user_info ? @user_info["username"] : nil
  end

  # Get user display name
  def display_name
    return nil unless @user_info
    (@user_info["first_name"] && @user_info["last_name"]) ?
      "#{@user_info["first_name"]} #{@user_info["last_name"]}" :
      @user_info["username"]
  end

  # Get user email
  def email
    @user_info ? @user_info["email"] : nil
  end

  # Check if token needs refresh
  def token_expired?
    return true unless @session[:token_expires_at]
    Time.now.to_i >= @session[:token_expires_at].to_i
  end

  # Refresh access token if needed
  def refresh_token_if_needed
    return true unless token_expired?
    return false unless @session[:refresh_token]

    oauth_strategy = MattermostOAuthStrategy.new
    new_token_data = oauth_strategy.refresh_access_token(@session[:refresh_token])

    if new_token_data
      @session[:access_token] = new_token_data[:access_token]
      @session[:refresh_token] = new_token_data[:refresh_token] if new_token_data[:refresh_token]
      @session[:token_expires_at] = new_token_data[:expires_at]
      true
    else
      # Token refresh failed, clear session
      UserAuth.logout(@session)
      false
    end
  end

  # Get user settings
  def user_settings
    return nil unless authenticated?
    UserSettings.find(user_id: user_id)
  end

  # Check if user can access a resource
  def can_access?(resource_user_id)
    return false unless authenticated?
    return true if admin?
    # Users can access their own resources
    return true if user_id == resource_user_id
    # Add additional permission logic here if needed
    false
  end

  # Check if user is an admin
  def admin?
    return false unless authenticated?
    return false unless user_id

    admin_ids = ENV["ARTISTE_ADMINS"]
    return false unless admin_ids

    # Split comma-separated list and check if current user ID is included
    admin_ids.split(",").map(&:strip).include?(user_id.to_s)
  end

  # Generate CSRF token for OAuth state
  def self.generate_state_token
    SecureRandom.hex(32)
  end

  # Verify CSRF token
  def self.verify_state_token(session, provided_state)
    return false unless provided_state
    return false unless session[:oauth_state]
    session[:oauth_state] == provided_state
  end

  # Store OAuth state in session
  def self.store_oauth_state(session, state)
    session[:oauth_state] = state
  end

  # Clear OAuth state from session
  def self.clear_oauth_state(session)
    session.delete(:oauth_state)
  end
end
