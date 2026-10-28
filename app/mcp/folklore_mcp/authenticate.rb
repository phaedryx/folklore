module FolkloreMcp
  # Turns an Authorization header into an Actor. Tokens are opaque: the
  # bearer value is hashed and looked up, never decoded.
  class Authenticate
    Error = Class.new(StandardError)
    Unauthenticated = Class.new(Error)
    Revoked = Class.new(Error)

    LAST_USED_INTERVAL = 60.seconds
    # RFC 9110: the auth scheme is case-insensitive.
    BEARER = /\ABearer +(\S+)\s*\z/i

    def self.call(header, agent: nil)
      new(header, agent:).call
    end

    def initialize(header, agent: nil)
      @header = header.to_s
      @agent = agent
    end

    def call
      plaintext = @header[BEARER, 1]
      raise Unauthenticated, "missing or invalid Authorization header" unless plaintext

      token = Token.find_by(token_digest: Token.digest(plaintext))
      raise Unauthenticated, "unknown token" unless token
      raise Revoked, "token revoked" if token.revoked?

      touch_last_used(token)
      Actor.for_token(token, agent: @agent)
    end

    private

    # One write per minute at most, so a busy agent does not turn every call
    # into an UPDATE.
    def touch_last_used(token)
      return if token.last_used_at && token.last_used_at > LAST_USED_INTERVAL.ago

      token.update_column(:last_used_at, Time.current)
    end
  end
end
