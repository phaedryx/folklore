module Tokens
  # Issues an opaque bearer token for one of the user's agents. The plaintext
  # is returned once and never stored.
  class Issue
    Result = Data.define(:token, :plaintext)

    def self.mutate(user:, agent_name:)
      new(user:, agent_name:).mutate
    end

    def initialize(user:, agent_name:)
      @user = user
      @agent_name = agent_name.to_s.strip
    end

    def mutate
      plaintext = Token::PREFIX + SecureRandom.base58(32)
      token = @user.tokens.create!(agent_name: @agent_name, token_digest: Token.digest(plaintext))
      Result.new(token:, plaintext:)
    end
  end
end
