module Tokens
  # Issues an opaque bearer token for one of the user's agents. The plaintext
  # is returned once and never stored. A shared token is held by several
  # agents, which tell themselves apart with the MCP `agent` argument.
  class Issue
    Result = Data.define(:token, :plaintext)

    def self.mutate(user:, agent_name:, scopes: Token::SCOPES, shared: false)
      new(user:, agent_name:, scopes:, shared:).mutate
    end

    def initialize(user:, agent_name:, scopes:, shared:)
      @user = user
      @agent_name = agent_name.to_s.strip
      @scopes = Array(scopes).map(&:to_s).compact_blank.uniq
      @shared = shared
    end

    def mutate
      plaintext = Token::PREFIX + SecureRandom.base58(32)
      token = @user.tokens.create!(agent_name: @agent_name, scopes: @scopes, shared: @shared, token_digest: Token.digest(plaintext))
      Result.new(token:, plaintext:)
    end
  end
end
