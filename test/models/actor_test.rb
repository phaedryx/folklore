require "test_helper"

class ActorTest < ActiveSupport::TestCase
  test "for_token defaults the agent to the token's agent name" do
    actor = Actor.for_token(tokens(:member_default))

    assert_equal users(:member), actor.user
    assert_equal tokens(:member_default), actor.token
    assert_equal "default", actor.agent
    assert_equal "member", actor.handle
  end

  test "for_token accepts an agent override" do
    actor = Actor.for_token(tokens(:member_default), agent: "ping")

    assert_equal "ping", actor.agent
    assert_equal tokens(:member_default), actor.token
  end

  test "for_token treats a blank override as no override" do
    assert_equal "default", Actor.for_token(tokens(:member_default), agent: "").agent
    assert_equal "default", Actor.for_token(tokens(:member_default), agent: nil).agent
  end

  test "for_token strips the override and rejects labels that are not slugs" do
    assert_equal "ping", Actor.for_token(tokens(:member_default), agent: " ping ").agent

    [ "a/b", "notes.md", "../x", "Ping", "a b", "-x", "x" * 65 ].each do |bad|
      assert_raises(Actor::InvalidAgentError, bad.inspect) { Actor.for_token(tokens(:member_default), agent: bad) }
    end
  end

  test "an MCP agent cannot pose as the web actor" do
    assert_raises(Actor::InvalidAgentError) { Actor.for_token(tokens(:member_default), agent: "web") }
  end

  test "for_user has no token and the web agent" do
    actor = Actor.for_user(users(:member))

    assert_nil actor.token
    assert_equal "web", actor.agent
    assert_equal "member", actor.handle
  end
end
