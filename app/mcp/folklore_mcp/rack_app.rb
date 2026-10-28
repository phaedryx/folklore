module FolkloreMcp
  # Rack app mounted at /mcp. Authenticates each request via the bearer
  # token, then dispatches to a per-request MCP::Server carrying the actor in
  # its server_context. Building the server per request is cheap (the tool
  # list is shared) and keeps server_context request-scoped.
  class RackApp
    def call(env)
      request = Rack::Request.new(env)
      actor = Authenticate.call(request.env["HTTP_AUTHORIZATION"])

      server = MCP::Server.new(
        name: "folklore",
        version: FolkloreMcp::VERSION,
        instructions: FolkloreMcp::SERVER_INSTRUCTIONS,
        tools: FolkloreMcp.tool_classes,
        server_context: { actor: }
      )
      # Host checking is Rails' job (config.hosts), so the transport's own
      # loopback-only check is off; stateless JSON keeps each POST self-contained.
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(
        server, stateless: true, enable_json_response: true, dns_rebinding_protection: false
      )
      transport.call(env)
    rescue Authenticate::Revoked => e
      unauthorized(e.message)
    rescue Authenticate::Unauthenticated => e
      unauthorized(e.message)
    end

    private

    def unauthorized(message)
      [
        401,
        { "content-type" => "application/json", "www-authenticate" => "Bearer" },
        [ { error: message }.to_json ]
      ]
    end
  end
end
