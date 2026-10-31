require "test_helper"

class CheckpointTest < ActiveSupport::TestCase
  test "dir_for places a token's own checkpoint under its agent name" do
    assert_equal "member/state/default", Checkpoint.dir_for(Actor.for_token(tokens(:member_default)))
    assert_equal "member/state/writer", Checkpoint.dir_for(Actor.for_token(tokens(:member_writeonly)))
    assert_equal "last_session.md", Checkpoint::NAME
  end

  # Keyed by token: a shared token's agents live under the token's own name, so
  # no `agent` it passes can reach another token's checkpoint.
  test "dir_for places a shared token's other agents under the token" do
    assert_equal "member/state/default/ping", Checkpoint.dir_for(Actor.for_token(tokens(:member_default), agent: "ping"))
    assert_equal "member/state/default/writer", Checkpoint.dir_for(Actor.for_token(tokens(:member_default), agent: "writer"))
    assert_equal "member/state/default", Checkpoint.dir_for(Actor.for_token(tokens(:member_default), agent: "default"))
  end

  test "dir_for raises when the actor has no handle" do
    user = User.create!(email: "new@example.com", name: "New")

    assert_raises(Checkpoint::NoHandleError) { Checkpoint.dir_for(Actor.for_user(user)) }
  end
end
