require "test_helper"

class Checkpoints::WriteTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
  end

  def write(content, actor: @actor)
    Checkpoints::Write.mutate(actor:, content:).asset
  end

  def read(actor = @actor)
    Checkpoints::Read.query(actor:)
  end

  test "writes the checkpoint to the agent's reserved state directory, owned by the user" do
    asset = write("picked up phase 4")

    assert_equal "last_session.md", asset.name
    assert_equal "member/state/default", asset.dir
    assert_equal users(:member).id, asset.owner_id
    assert_equal "picked up phase 4", asset.content
    assert_equal "text/markdown", asset.content_type
    assert_equal "default", asset.created_by_agent
  end

  test "overwrites in place rather than accumulating checkpoints" do
    write("first")

    assert_no_difference -> { Asset.live.count } do
      write("second")
    end

    assert_equal "second", read.content
  end

  test "keeps the previous checkpoint as a version" do
    asset = write("first")

    write("second")

    assert_equal [ "first" ], Version.where(asset_id: asset.id).order(:id).map(&:content)
  end

  test "each member gets their own checkpoint" do
    write("mine")
    write("theirs", actor: actor_for(:other_default))

    assert_equal "mine", read.content
    assert_equal "theirs", read(actor_for(:other_default)).content
  end

  test "two agents on one token keep separate checkpoints" do
    ping = actor_for(:member_default, agent: "ping")
    pong = actor_for(:member_default, agent: "pong")

    write("ping's place", actor: ping)
    write("pong's place", actor: pong)

    assert_equal "ping's place", read(ping).content
    assert_equal "pong's place", read(pong).content
    assert_equal "member/state/default/pong", read(pong).dir
    assert_nil read
  end

  test "a shared token passing another token's agent name cannot read or overwrite that token's checkpoint" do
    writer = actor_for(:member_writeonly)
    write("writer's own place", actor: writer)
    borrowed = actor_for(:member_default, agent: "writer")

    assert_nil read(borrowed)
    write("borrowed", actor: borrowed)

    assert_equal "writer's own place", read(writer).content
    assert_equal "member/state/writer", read(writer).dir
    assert_equal "member/state/default/writer", read(borrowed).dir
  end

  test "refuses blank content rather than silently keeping or clearing the old checkpoint" do
    write("real")

    [ "", "   ", nil ].each do |blank|
      assert_raises(Checkpoints::EmptyContentError) { write(blank) }
    end

    assert_equal "real", read.content
  end

  test "rewrites a checkpoint that was deleted" do
    gone = write("gone")
    Assets::Delete.mutate(actor: @actor, slug: gone.slug)

    fresh = write("back")

    refute_equal gone.id, fresh.id
    assert_equal "back", read.content
  end

  test "a web session has no checkpoint of its own" do
    assert_raises(Checkpoints::NoAgentError) { write("x", actor: Actor.for_user(users(:member))) }
  end

  test "raises NoHandleError when the user has not claimed a handle" do
    handleless = User.create!(email: "nohandle@example.com", name: "No Handle")
    token = Token.create!(user: handleless, agent_name: "default", token_digest: Token.digest("flk_test_nohandle"))

    assert_raises(Checkpoint::NoHandleError) { write("x", actor: Actor.for_token(token)) }
  end

  test "reports whether the write changed anything" do
    assert Checkpoints::Write.mutate(actor: @actor, content: "first").changed
    assert Checkpoints::Write.mutate(actor: @actor, content: "second").changed
    refute Checkpoints::Write.mutate(actor: @actor, content: "second").changed
  end
end
