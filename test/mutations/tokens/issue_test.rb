require "test_helper"

class Tokens::IssueTest < ActiveSupport::TestCase
  test "issues a token for an agent and returns the plaintext once" do
    result = Tokens::Issue.mutate(user: users(:member), agent_name: "ping")

    assert_match(/\Aflk_[1-9A-HJ-NP-Za-km-z]{32}\z/, result.plaintext)
    assert_equal "ping", result.token.agent_name
    assert_equal users(:member), result.token.user
    assert_equal Token.digest(result.plaintext), result.token.token_digest
    assert_equal %w[read write], result.token.scopes
  end

  test "stores only the digest" do
    result = Tokens::Issue.mutate(user: users(:member), agent_name: "ping")

    refute_includes Token.pluck(:token_digest), result.plaintext
    assert_equal result.token, Token.find_by(token_digest: Token.digest(result.plaintext))
  end

  test "requires an agent name" do
    assert_raises(ActiveRecord::RecordInvalid) { Tokens::Issue.mutate(user: users(:member), agent_name: " ") }
  end
end

class Tokens::IssueScopesTest < ActiveSupport::TestCase
  test "issues a read-only token when asked" do
    result = Tokens::Issue.mutate(user: users(:member), agent_name: "reader", scopes: %w[read])

    assert_equal %w[read], result.token.reload.scopes
  end

  test "refuses no scopes and unknown scopes" do
    assert_raises(ActiveRecord::RecordInvalid) { Tokens::Issue.mutate(user: users(:member), agent_name: "a", scopes: []) }
    assert_raises(ActiveRecord::RecordInvalid) { Tokens::Issue.mutate(user: users(:member), agent_name: "b", scopes: %w[admin]) }
  end

  test "the read-only fixture carries only the read scope" do
    assert_equal %w[read], tokens(:member_readonly).scopes
    refute_predicate tokens(:member_readonly), :writable?
    assert_predicate tokens(:member_default), :writable?
  end
end
