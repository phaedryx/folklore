module Settings
  module TokensHelper
    # The client config for a freshly issued token: the same shape
    # `bin/setup` prints.
    def mcp_config_json(plaintext)
      JSON.pretty_generate(
        "mcpServers" => {
          "folklore" => {
            "type" => "http",
            "url" => "#{request.base_url}/mcp",
            "headers" => { "Authorization" => "Bearer #{plaintext}" }
          }
        }
      )
    end
  end
end
