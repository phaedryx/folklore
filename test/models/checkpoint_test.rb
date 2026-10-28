require "test_helper"

class CheckpointTest < ActiveSupport::TestCase
  test "dir_for places the checkpoint under the agent's state directory" do
    actor = Actor.for_token(tokens(:member_default), agent: "ping")

    assert_equal "member/state/ping", Checkpoint.dir_for(actor)
    assert_equal "last_session.md", Checkpoint::NAME
  end

  test "dir_for raises when the actor has no handle" do
    user = User.create!(email: "new@example.com", name: "New")

    assert_raises(Checkpoint::NoHandleError) { Checkpoint.dir_for(Actor.for_user(user)) }
  end
end
