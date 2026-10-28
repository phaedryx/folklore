require "test_helper"

class TokenTest < ActiveSupport::TestCase
  test "requires user, agent_name and token_digest" do
    token = Token.new
    refute token.valid?
    assert_includes token.errors[:user], "must exist"
    assert_includes token.errors[:agent_name], "can't be blank"
    assert_includes token.errors[:token_digest], "can't be blank"
  end

  test "agent_name must be a lowercase slug and never web" do
    %w[ping pong_2 coordinator-1 a].each do |ok|
      assert Token.new(user: users(:member), agent_name: ok, token_digest: Token.digest(ok)).valid?, ok
    end
    [ "Ping", "a b", "a/b", "a.b", "web", "-x" ].each do |bad|
      refute Token.new(user: users(:member), agent_name: bad, token_digest: Token.digest(bad)).valid?, bad
    end
  end

  test "token_digest is unique" do
    digest = Token.digest("flk_abc")
    Token.create!(user: users(:member), agent_name: "a", token_digest: digest)
    dup = Token.new(user: users(:member), agent_name: "b", token_digest: digest)
    refute dup.valid?
    assert_includes dup.errors[:token_digest], "has already been taken"
  end

  test "digest is the hex SHA-256 of the plaintext" do
    assert_equal Digest::SHA256.hexdigest("flk_abc"), Token.digest("flk_abc")
  end

  test "scopes default to read and write" do
    token = Token.create!(user: users(:member), agent_name: "a", token_digest: Token.digest("x"))
    assert_equal %w[read write], token.reload.scopes
  end

  test "active scope excludes revoked" do
    refute_includes Token.active, tokens(:member_revoked)
    assert_includes Token.active, tokens(:member_default)
  end

  test "revoked? reflects revoked_at" do
    refute tokens(:member_default).revoked?
    assert tokens(:member_revoked).revoked?
  end

  test "fixture digests match their documented plaintexts" do
    assert_equal Token.digest("flk_test_member"), tokens(:member_default).token_digest
    assert_equal Token.digest("flk_test_other"), tokens(:other_default).token_digest
  end
end
