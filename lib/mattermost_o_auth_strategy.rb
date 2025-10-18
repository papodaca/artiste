class MattermostOAuthStrategy
  attr_reader :redirect_uri, :authorise_uri, :token_uri

  def initialize
    @mattermost_url = ENV["MATTERMOST_OAUTH_URL"] || ENV["MATTERMOST_URL"]
    @client_id = ENV["MATTERMOST_CLIENT_ID"]
    @client_secret = ENV["MATTERMOST_CLIENT_SECRET"]
    @redirect_uri = ENV["MATTERMOST_REDIRECT_URI"] || "http://localhost:4567/auth/callback"
    @authorise_uri = "#{@mattermost_url}/oauth/authorize"
    @token_uri = "#{@mattermost_url}/oauth/access_token"

    raise "MATTERMOST_URL is required" unless @mattermost_url
    raise "MATTERMOST_CLIENT_ID is required" unless @client_id
    raise "MATTERMOST_CLIENT_SECRET is required" unless @client_secret
  end

  # Generate authorization URL
  def authorize_url(state: nil, scope: nil)
    params = {
      client_id: @client_id,
      redirect_uri: redirect_uri,
      response_type: 'code'
    }
    params[:state] = state if state
    params[:scope] = scope if scope
    
    # Build URL manually
    uri = URI(authorise_uri)
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  # Exchange authorization code for access token
  def get_access_token(authorization_code)
    begin
      response = HTTParty.post(
        token_uri,
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded'
        },
        body: {
          client_id: @client_id,
          client_secret: @client_secret,
          code: authorization_code,
          redirect_uri: @redirect_uri,
          grant_type: 'authorization_code'
        }
      )
      
      if response.code == 200
        token_data = JSON.parse(response.body)
        
        # Calculate expires_at if expires_in is provided
        expires_at = nil
        if token_data['expires_in']
          expires_at = Time.now.to_i + token_data['expires_in'].to_i
        end
        
        {
          access_token: token_data['access_token'],
          refresh_token: token_data['refresh_token'],
          expires_at: expires_at,
          token_type: token_data['token_type']
        }
      else
        puts "HTTP Error: #{response.code} - #{response.body}"
        nil
      end
    rescue => e
      puts "Unexpected error getting access token: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
      nil
    end
  end

  # Get user information using access token
  def get_user_info(access_token)
    begin
      response = HTTParty.get(
        "#{@mattermost_url}/api/v4/users/me",
        headers: {
          'Authorization' => "Bearer #{access_token}"
        }
      )
      
      if response.code == 200
        JSON.parse(response.body)
      else
        puts "Error getting user info: #{response.code} - #{response.body}"
        nil
      end
    rescue => e
      puts "Unexpected error getting user info: #{e.message}"
      nil
    end
  end

  # Refresh access token using refresh token
  def refresh_access_token(refresh_token)
    begin
      response = HTTParty.post(
        token_uri,
        headers: {
          'Content-Type' => 'application/x-www-form-urlencoded'
        },
        body: {
          client_id: @client_id,
          client_secret: @client_secret,
          grant_type: 'refresh_token',
          refresh_token: refresh_token
        }
      )
      
      if response.code == 200
        token_data = JSON.parse(response.body)
        
        # Calculate expires_at if expires_in is provided
        expires_at = nil
        if token_data['expires_in']
          expires_at = Time.now.to_i + token_data['expires_in'].to_i
        end
        
        {
          access_token: token_data['access_token'],
          refresh_token: token_data['refresh_token'],
          expires_at: expires_at,
          token_type: token_data['token_type']
        }
      else
        puts "Error refreshing token: #{response.code} - #{response.body}"
        nil
      end
    rescue => e
      puts "Unexpected error refreshing token: #{e.message}"
      nil
    end
  end
end