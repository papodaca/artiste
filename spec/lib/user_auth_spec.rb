require "spec_helper"

RSpec.describe UserAuth do
  let(:session) { {} }
  let(:user_auth) { UserAuth.new(session) }

  describe "#authenticated?" do
    it "returns false when user_info and access_token are nil" do
      expect(user_auth.authenticated?).to be_falsey
    end

    it "returns false when user_info is nil" do
      session[:access_token] = "test-token"
      expect(user_auth.authenticated?).to be_falsey
    end

    it "returns false when access_token is nil" do
      session[:user_info] = {id: "123", username: "test"}.to_json
      expect(user_auth.authenticated?).to be_falsey
    end

    it "returns true when both user_info and access_token are present" do
      session[:access_token] = "test-token"
      session[:user_info] = {id: "123", username: "test"}.to_json
      expect(user_auth.authenticated?).to be_truthy
    end
  end

  describe ".authenticate" do
    let(:access_token_data) do
      {
        access_token: "test-access-token",
        refresh_token: "test-refresh-token",
        expires_at: Time.now.to_i + 3600,
        token_type: "Bearer"
      }
    end
    let(:user_info) do
      {
        "id" => "user-123",
        "username" => "testuser",
        "email" => "test@example.com",
        "first_name" => "Test",
        "last_name" => "User"
      }
    end

    before do
      @user_settings = double("user_settings")
      allow(@user_settings).to receive(:username=)
      allow(@user_settings).to receive(:save)
      allow(UserSettings).to receive(:get_or_create_for_user).and_return(@user_settings)
    end

    it "stores authentication data in session" do
      result = UserAuth.authenticate(session, access_token_data, user_info)

      expect(result).to be_truthy
      expect(session[:access_token]).to eq("test-access-token")
      expect(session[:refresh_token]).to eq("test-refresh-token")
      expect(session[:token_expires_at]).to eq(access_token_data[:expires_at])
      expect(session[:user_info]).to eq(user_info.to_json)
      expect(session[:authenticated_at]).to be_a(Integer)
    end

    it "creates or updates user settings" do
      mock_user_settings = double("user_settings")
      allow(UserSettings).to receive(:get_or_create_for_user).and_return(mock_user_settings)
      expect(mock_user_settings).to receive(:username=).with("testuser")
      expect(mock_user_settings).to receive(:save)

      UserAuth.authenticate(session, access_token_data, user_info)
    end

    it "returns false when access_token_data is nil" do
      result = UserAuth.authenticate(session, nil, user_info)
      expect(result).to be_falsey
    end

    it "returns false when user_info is nil" do
      result = UserAuth.authenticate(session, access_token_data, nil)
      expect(result).to be_falsey
    end
  end

  describe ".logout" do
    it "clears the session" do
      session[:access_token] = "test-token"
      session[:user_info] = {id: "123"}.to_json

      UserAuth.logout(session)

      expect(session).to be_empty
    end
  end

  describe "#user_id" do
    it "returns user ID from user_info" do
      session[:user_info] = {id: "user-123", username: "test"}.to_json
      expect(user_auth.user_id).to eq("user-123")
    end

    it "returns nil when user_info is not present" do
      expect(user_auth.user_id).to be_nil
    end
  end

  describe "#username" do
    it "returns username from user_info" do
      session[:user_info] = {id: "user-123", username: "testuser"}.to_json
      expect(user_auth.username).to eq("testuser")
    end

    it "returns nil when user_info is not present" do
      expect(user_auth.username).to be_nil
    end
  end

  describe "#display_name" do
    it "returns first_name and last_name when both are present" do
      session[:user_info] = {
        id: "user-123",
        username: "testuser",
        first_name: "Test",
        last_name: "User"
      }.to_json
      expect(user_auth.display_name).to eq("Test User")
    end

    it "returns username when first_name or last_name is missing" do
      session[:user_info] = {
        id: "user-123",
        username: "testuser",
        first_name: "Test"
      }.to_json
      expect(user_auth.display_name).to eq("testuser")
    end

    it "returns nil when user_info is not present" do
      expect(user_auth.display_name).to be_nil
    end
  end

  describe "#email" do
    it "returns email from user_info" do
      session[:user_info] = {id: "user-123", email: "test@example.com"}.to_json
      expect(user_auth.email).to eq("test@example.com")
    end

    it "returns nil when user_info is not present" do
      expect(user_auth.email).to be_nil
    end
  end

  describe "#token_expired?" do
    it "returns true when token_expires_at is not set" do
      expect(user_auth.token_expired?).to be_truthy
    end

    it "returns true when token is expired" do
      session[:token_expires_at] = Time.now.to_i - 3600
      expect(user_auth.token_expired?).to be_truthy
    end

    it "returns false when token is not expired" do
      session[:token_expires_at] = Time.now.to_i + 3600
      expect(user_auth.token_expired?).to be_falsey
    end
  end

  describe "#refresh_token_if_needed" do
    let(:oauth_strategy) { double("oauth_strategy") }
    let(:new_token_data) do
      {
        access_token: "new-access-token",
        refresh_token: "new-refresh-token",
        expires_at: Time.now.to_i + 3600,
        token_type: "Bearer"
      }
    end

    before do
      allow(MattermostOAuthStrategy).to receive(:new).and_return(oauth_strategy)
    end

    context "when token is not expired" do
      before do
        session[:token_expires_at] = Time.now.to_i + 3600
      end

      it "returns true without refreshing" do
        expect(oauth_strategy).not_to receive(:refresh_access_token)
        expect(user_auth.refresh_token_if_needed).to be_truthy
      end
    end

    context "when token is expired and refresh succeeds" do
      before do
        session[:token_expires_at] = Time.now.to_i - 3600
        session[:refresh_token] = "old-refresh-token"
        allow(oauth_strategy).to receive(:refresh_access_token).and_return(new_token_data)
      end

      it "updates session with new token data" do
        result = user_auth.refresh_token_if_needed

        expect(result).to be_truthy
        expect(session[:access_token]).to eq("new-access-token")
        expect(session[:refresh_token]).to eq("new-refresh-token")
        expect(session[:token_expires_at]).to eq(new_token_data[:expires_at])
      end
    end

    context "when token is expired and refresh fails" do
      before do
        session[:token_expires_at] = Time.now.to_i - 3600
        session[:refresh_token] = "old-refresh-token"
        allow(oauth_strategy).to receive(:refresh_access_token).and_return(nil)
      end

      it "clears session and returns false" do
        expect(UserAuth).to receive(:logout).with(session)
        expect(user_auth.refresh_token_if_needed).to be_falsey
      end
    end

    context "when no refresh token is available" do
      before do
        session[:token_expires_at] = Time.now.to_i - 3600
      end

      it "returns false" do
        expect(user_auth.refresh_token_if_needed).to be_falsey
      end
    end
  end

  describe "#user_settings" do
    let(:mock_user_settings) { double("user_settings") }

    before do
      allow(UserSettings).to receive(:find).and_return(mock_user_settings)
    end

    it "returns user settings when authenticated" do
      session[:access_token] = "test-token"
      session[:user_info] = {id: "user-123"}.to_json

      expect(UserSettings).to receive(:find).with(user_id: "user-123")
      expect(user_auth.user_settings).to eq(mock_user_settings)
    end

    it "returns nil when not authenticated" do
      expect(user_auth.user_settings).to be_nil
    end
  end

  describe "#can_access?" do
    before do
      session[:access_token] = "test-token"
      session[:user_info] = {id: "user-123"}.to_json
    end

    it "returns true for own resources" do
      expect(user_auth.can_access?("user-123")).to be_truthy
    end

    it "returns false for other users resources" do
      expect(user_auth.can_access?("user-456")).to be_falsey
    end

    it "returns false when not authenticated" do
      session.clear
      expect(user_auth.can_access?("user-123")).to be_falsey
    end
  end

  describe ".generate_state_token" do
    it "generates a 32-character hex string" do
      token = UserAuth.generate_state_token
      expect(token).to match(/\A[a-f0-9]{64}\z/)
      expect(token.length).to eq(64)
    end

    it "generates different tokens on multiple calls" do
      token1 = UserAuth.generate_state_token
      token2 = UserAuth.generate_state_token
      expect(token1).not_to eq(token2)
    end
  end

  describe ".verify_state_token" do
    let(:state) { "test-state-token" }

    before do
      session[:oauth_state] = state
    end

    it "returns true when state matches" do
      expect(UserAuth.verify_state_token(session, state)).to be_truthy
    end

    it "returns false when state does not match" do
      expect(UserAuth.verify_state_token(session, "wrong-state")).to be_falsey
    end

    it "returns false when no state is provided" do
      expect(UserAuth.verify_state_token(session, nil)).to be_falsey
    end

    it "returns false when no state is stored in session" do
      session.clear
      expect(UserAuth.verify_state_token(session, state)).to be_falsey
    end
  end

  describe ".store_oauth_state" do
    let(:state) { "test-state-token" }

    it "stores state in session" do
      UserAuth.store_oauth_state(session, state)
      expect(session[:oauth_state]).to eq(state)
    end
  end

  describe ".clear_oauth_state" do
    before do
      session[:oauth_state] = "test-state-token"
    end

    it "removes state from session" do
      UserAuth.clear_oauth_state(session)
      expect(session).not_to have_key(:oauth_state)
    end
  end

  describe "#admin?" do
    context "when user is not authenticated" do
      it "returns false" do
        expect(user_auth.admin?).to be_falsey
      end
    end

    context "when user is authenticated but ARTISTE_ADMINS is not set" do
      before do
        session[:access_token] = "test-token"
        session[:user_info] = {id: "user-123", username: "testuser"}.to_json
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return(nil)
      end

      it "returns false" do
        expect(user_auth.admin?).to be_falsey
      end
    end

    context "when user is authenticated and ARTISTE_ADMINS is set" do
      before do
        session[:access_token] = "test-token"
        session[:user_info] = {id: "user-123", username: "testuser"}.to_json
      end

      it "returns true when user ID is in the admin list" do
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return("user-123,user-456")
        expect(user_auth.admin?).to be_truthy
      end

      it "returns false when user ID is not in the admin list" do
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return("user-456,user-789")
        expect(user_auth.admin?).to be_falsey
      end

      it "handles whitespace in admin list" do
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return(" user-123 , user-456 ")
        expect(user_auth.admin?).to be_truthy
      end

      it "handles single admin ID" do
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return("user-123")
        expect(user_auth.admin?).to be_truthy
      end

      it "handles empty admin list" do
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return("")
        expect(user_auth.admin?).to be_falsey
      end

      it "converts user ID to string for comparison" do
        session[:user_info] = {id: 123, username: "testuser"}.to_json
        allow(ENV).to receive(:[]).with("ARTISTE_ADMINS").and_return("123,456")
        expect(user_auth.admin?).to be_truthy
      end
    end
  end
end
