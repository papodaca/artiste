class MattermostClient
  include HTTParty

  def self.setup(uri, token)
    self.base_uri(uri)
    self.headers({
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    })
  end
end
