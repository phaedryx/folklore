module Tokens
  # A user's tokens, newest first. Scoped to the user, so a lookup by id
  # through it cannot reach another user's token.
  class List
    def self.query(user:)
      user.tokens.order(created_at: :desc, id: :desc)
    end
  end
end
