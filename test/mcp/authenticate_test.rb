require "test_helper"

class FolkloreMcp::AuthenticateTest < ActiveSupport::TestCase
  test "a valid bearer token yields an actor for its user and agent" do
    actor = FolkloreMcp::Authenticate.call("Bearer flk_test_member")

    assert_equal users(:member), actor.user
    assert_equal tokens(:member_default), actor.token
    assert_equal "default", actor.agent
  end

  test "an unknown token is unauthenticated" do
    assert_raises(FolkloreMcp::Authenticate::Unauthenticated) do
      FolkloreMcp::Authenticate.call("Bearer flk_nope")
    end
  end

  test "a revoked token fails closed" do
    assert_raises(FolkloreMcp::Authenticate::Revoked) do
      FolkloreMcp::Authenticate.call("Bearer flk_test_member_revoked")
    end
  end

  test "a missing header is unauthenticated" do
    assert_raises(FolkloreMcp::Authenticate::Unauthenticated) { FolkloreMcp::Authenticate.call(nil) }
    assert_raises(FolkloreMcp::Authenticate::Unauthenticated) { FolkloreMcp::Authenticate.call("") }
  end

  test "a non-bearer scheme is unauthenticated" do
    assert_raises(FolkloreMcp::Authenticate::Unauthenticated) do
      FolkloreMcp::Authenticate.call("Basic #{Base64.strict_encode64('x:y')}")
    end
  end

  test "last_used_at is written on first use and then at most once a minute" do
    token = tokens(:member_default)
    assert_nil token.last_used_at

    FolkloreMcp::Authenticate.call("Bearer flk_test_member")
    first = token.reload.last_used_at
    assert_in_delta Time.current, first, 5.seconds

    token.update_column(:last_used_at, 30.seconds.ago)
    FolkloreMcp::Authenticate.call("Bearer flk_test_member")
    assert_in_delta 30.seconds.ago, token.reload.last_used_at, 2.seconds

    token.update_column(:last_used_at, 2.minutes.ago)
    FolkloreMcp::Authenticate.call("Bearer flk_test_member")
    assert_in_delta Time.current, token.reload.last_used_at, 5.seconds
  end
end
