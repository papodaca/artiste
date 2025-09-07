class MattermostClient
  include HTTParty

  def self.setup(uri, token)
    base_uri(uri)
    headers({
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    })
    self
  end
end
