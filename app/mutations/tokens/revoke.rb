module Tokens
  class Revoke
    Error = Class.new(StandardError)
    ForbiddenError = Class.new(Error)
    AlreadyRevokedError = Class.new(Error)

    def self.mutate(token:, actor:)
      new(token:, actor:).mutate
    end

    def initialize(token:, actor:)
      @token = token
      @actor = actor
    end

    def mutate
      raise ForbiddenError, "token belongs to another user" unless @token.user_id == @actor.user.id
      raise AlreadyRevokedError, "token already revoked" if @token.revoked?

      @token.update!(revoked_at: Time.current)
      @token
    end
  end
end
