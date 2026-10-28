require "test_helper"

class Checkpoints::ReadTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
  end

  def read(actor = @actor)
    Checkpoints::Read.query(actor:)
  end

  test "returns nil when the agent has never written a checkpoint" do
    assert_nil read
  end

  test "returns the agent's own checkpoint" do
    Checkpoints::Write.mutate(actor: @actor, content: "where I left off")

    assert_equal "where I left off", read.content
  end

  test "an agent override reads that agent's checkpoint" do
    Checkpoints::Write.mutate(actor: actor_for(:member_default, agent: "pong"), content: "pong's")

    assert_nil read
    assert_equal "pong's", read(actor_for(:member_default, agent: "pong")).content
  end

  test "does not return another member's checkpoint for the same agent name" do
    Checkpoints::Write.mutate(actor: actor_for(:other_default), content: "theirs")

    assert_nil read
  end

  test "ignores a deleted checkpoint" do
    asset = Checkpoints::Write.mutate(actor: @actor, content: "gone").asset
    Assets::Delete.mutate(actor: @actor, slug: asset.slug)

    assert_nil read
  end

  test "ignores a same-named file outside the reserved state directory" do
    Assets::Create.mutate(actor: @actor, path: "member/notes", name: "last_session.md", content: "decoy")
    Assets::Create.mutate(actor: @actor, path: "member/state/default/old", name: "last_session.md", content: "decoy", reserved: true)

    assert_nil read
  end

  test "a web session reads nothing" do
    assert_nil read(Actor.for_user(users(:member)))
  end

  test "raises NoHandleError when the user has not claimed a handle" do
    handleless = User.create!(email: "nohandle@example.com", name: "No Handle")
    token = Token.create!(user: handleless, agent_name: "default", token_digest: Token.digest("flk_test_nohandle"))

    assert_raises(Checkpoint::NoHandleError) { read(Actor.for_token(token)) }
  end
end
