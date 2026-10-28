module Tokens
  # Issues an opaque bearer token for one of the user's agents. The plaintext
  # is returned once and never stored.
  class Issue
    Result = Data.define(:token, :plaintext)

    def self.mutate(user:, agent_name:, scopes: Token::SCOPES)
      new(user:, agent_name:, scopes:).mutate
    end

    def initialize(user:, agent_name:, scopes:)
      @user = user
      @agent_name = agent_name.to_s.strip
      @scopes = Array(scopes).map(&:to_s).compact_blank.uniq
    end

    def mutate
      plaintext = Token::PREFIX + SecureRandom.base58(32)
      token = @user.tokens.create!(agent_name: @agent_name, scopes: @scopes, token_digest: Token.digest(plaintext))
      Result.new(token:, plaintext:)
    end
  end
end
