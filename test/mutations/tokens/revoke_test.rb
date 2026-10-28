require "test_helper"

class Tokens::RevokeTest < ActiveSupport::TestCase
  test "revokes the caller's own token" do
    token = tokens(:member_default)

    Tokens::Revoke.mutate(token:, actor: Actor.for_user(users(:member)))

    assert token.reload.revoked?
  end

  test "refuses to revoke another user's token" do
    assert_raises(Tokens::Revoke::ForbiddenError) do
      Tokens::Revoke.mutate(token: tokens(:member_default), actor: Actor.for_user(users(:other)))
    end
    refute tokens(:member_default).reload.revoked?
  end

  test "revoking twice is an error" do
    assert_raises(Tokens::Revoke::AlreadyRevokedError) do
      Tokens::Revoke.mutate(token: tokens(:member_revoked), actor: Actor.for_user(users(:member)))
    end
  end
end
