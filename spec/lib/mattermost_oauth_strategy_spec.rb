require 'spec_helper'

RSpec.describe MattermostOAuthStrategy do
  let(:mattermost_url) { 'https://mattermost.example.com' }
  let(:client_id) { 'test-client-id' }
  let(:client_secret) { 'test-client-secret' }
  let(:redirect_uri) { 'http://localhost:4567/auth/callback' }

  before do
    ENV['MATTERMOST_URL'] = mattermost_url
    ENV['MATTERMOST_CLIENT_ID'] = client_id
    ENV['MATTERMOST_CLIENT_SECRET'] = client_secret
    ENV['MATTERMOST_REDIRECT_URI'] = redirect_uri
  end

  after do
    ENV.delete('MATTERMOST_URL')
    ENV.delete('MATTERMOST_CLIENT_ID')
    ENV.delete('MATTERMOST_CLIENT_SECRET')
    ENV.delete('MATTERMOST_REDIRECT_URI')
  end

  describe '#initialize' do
    it 'initializes with environment variables' do
      strategy = MattermostOAuthStrategy.new
      expect(strategy.instance_variable_get(:@mattermost_url)).to eq(mattermost_url)
      expect(strategy.instance_variable_get(:@client_id)).to eq(client_id)
      expect(strategy.instance_variable_get(:@client_secret)).to eq(client_secret)
      expect(strategy.instance_variable_get(:@redirect_uri)).to eq(redirect_uri)
    end

    it 'raises error when MATTERMOST_URL is missing' do
      ENV.delete('MATTERMOST_URL')
      expect { MattermostOAuthStrategy.new }.to raise_error('MATTERMOST_URL is required')
    end

    it 'raises error when MATTERMOST_CLIENT_ID is missing' do
      ENV.delete('MATTERMOST_CLIENT_ID')
      expect { MattermostOAuthStrategy.new }.to raise_error('MATTERMOST_CLIENT_ID is required')
    end

    it 'raises error when MATTERMOST_CLIENT_SECRET is missing' do
      ENV.delete('MATTERMOST_CLIENT_SECRET')
      expect { MattermostOAuthStrategy.new }.to raise_error('MATTERMOST_CLIENT_SECRET is required')
    end
  end

  describe '#authorize_url' do
    let(:strategy) { MattermostOAuthStrategy.new }
    let(:state) { 'test-state' }

    it 'generates authorization URL with state' do
      url = strategy.authorize_url(state: state)
      expect(url).to include('/oauth/authorize')
      expect(url).to include('response_type=code')
      expect(url).to include('redirect_uri=' + CGI.escape(redirect_uri))
      expect(url).to include('state=' + state)
    end

    it 'generates authorization URL without state' do
      url = strategy.authorize_url
      expect(url).to include('/oauth/authorize')
      expect(url).to include('response_type=code')
      expect(url).to include('redirect_uri=' + CGI.escape(redirect_uri))
      expect(url).not_to include('state=')
    end

    it 'generates authorization URL with scope' do
      url = strategy.authorize_url(scope: 'read write')
      expect(url).to include('scope=' + CGI.escape('read write'))
    end
  end

  describe '#get_access_token' do
    let(:strategy) { MattermostOAuthStrategy.new }
    let(:authorization_code) { 'test-auth-code' }

    context 'when successful' do
      before do
        mock_response = double('response', code: 200, body: {
          access_token: 'access-token-123',
          refresh_token: 'refresh-token-456',
          expires_in: 3600,
          token_type: 'Bearer'
        }.to_json)
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it 'returns access token data' do
        result = strategy.get_access_token(authorization_code)
        expect(result).to be_a(Hash)
        expect(result[:access_token]).to eq('access-token-123')
        expect(result[:refresh_token]).to eq('refresh-token-456')
        expect(result[:token_type]).to eq('Bearer')
        expect(result[:expires_at]).to be_a(Integer)
      end
    end

    context 'when HTTP error occurs' do
      before do
        mock_response = double('response', code: 400, body: 'Bad Request')
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it 'returns nil on HTTP error' do
        expect(strategy.get_access_token(authorization_code)).to be_nil
      end
    end
  end

  describe '#get_user_info' do
    let(:strategy) { MattermostOAuthStrategy.new }
    let(:access_token) { 'test-access-token' }
    let(:user_data) do
      {
        'id' => 'user-123',
        'username' => 'testuser',
        'email' => 'test@example.com',
        'first_name' => 'Test',
        'last_name' => 'User'
      }
    end

    context 'when successful' do
      before do
        mock_response = double('response', code: 200, body: user_data.to_json)
        allow(HTTParty).to receive(:get).and_return(mock_response)
      end

      it 'returns user information' do
        result = strategy.get_user_info(access_token)
        expect(result).to eq(user_data)
      end
    end

    context 'when API error occurs' do
      before do
        mock_response = double('response', code: 401, body: 'Unauthorized')
        allow(HTTParty).to receive(:get).and_return(mock_response)
      end

      it 'returns nil on API error' do
        expect(strategy.get_user_info(access_token)).to be_nil
      end
    end
  end

  describe '#refresh_access_token' do
    let(:strategy) { MattermostOAuthStrategy.new }
    let(:refresh_token) { 'test-refresh-token' }

    context 'when successful' do
      before do
        mock_response = double('response', code: 200, body: {
          access_token: 'new-access-token',
          refresh_token: 'new-refresh-token',
          expires_in: 3600,
          token_type: 'Bearer'
        }.to_json)
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it 'returns new access token data' do
        result = strategy.refresh_access_token(refresh_token)
        expect(result).to be_a(Hash)
        expect(result[:access_token]).to eq('new-access-token')
        expect(result[:refresh_token]).to eq('new-refresh-token')
        expect(result[:token_type]).to eq('Bearer')
        expect(result[:expires_at]).to be_a(Integer)
      end
    end

    context 'when refresh fails' do
      before do
        mock_response = double('response', code: 400, body: 'Invalid refresh token')
        allow(HTTParty).to receive(:post).and_return(mock_response)
      end

      it 'returns nil on refresh error' do
        expect(strategy.refresh_access_token(refresh_token)).to be_nil
      end
    end
  end
end