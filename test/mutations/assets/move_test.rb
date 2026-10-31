require "test_helper"

class Assets::MoveTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "hi")
  end

  test "moves to a new directory, keeping the slug, and writes an asset_moved event naming both locations" do
    moved = Assets::Move.mutate(actor: actor_for(:member_default, agent: "pong"), slug: @asset.slug, path: "member/archive-2026/notes")

    assert_equal @asset.slug, moved.slug
    assert_equal "member/archive-2026/notes/hello.md", @asset.reload.location
    assert_equal "pong", @asset.updated_by_agent
    assert_equal 1, @asset.lock_version
    event = Event.where(action: "asset_moved").sole
    assert_equal({ "from" => "member/notes/hello.md", "to" => "member/archive-2026/notes/hello.md" }, event.metadata)
  end

  test "renames as it moves when given a name" do
    Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/plans", name: "plan.md")

    assert_equal "member/plans/plan.md", @asset.reload.location
  end

  test "a move to where it already is writes nothing" do
    Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/notes")

    assert_equal 0, @asset.reload.lock_version
    assert_empty Event.where(action: "asset_moved")
  end

  test "refuses to move a checkpoint out of its reserved directory, where get_last_session looks for it" do
    checkpoint = Checkpoints::Write.mutate(actor: @actor, content: "state").asset
    dir = checkpoint.dir

    assert_raises(Asset::ReservedDirError) { Assets::Move.mutate(actor: @actor, slug: checkpoint.slug, path: "member/notes") }
    assert_equal dir, checkpoint.reload.dir
  end

  test "keeps links to the asset, which are by slug" do
    source = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "src.md", content: "see [[#{@asset.slug}]]")

    Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/elsewhere")

    assert_equal [ source ], Links::Backlinks.query(asset: @asset.reload).to_a
  end

  test "refuses a taken location, a reserved or invalid path, another workspace, and an archived asset" do
    Assets::Create.mutate(actor: @actor, path: "member/other", name: "hello.md", content: "")

    taken = assert_raises(Assets::NameTakenError) { Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/other") }
    assert_equal "member/other/hello.md already exists", taken.message
    assert_raises(Asset::ReservedDirError) { Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/state/x") }
    assert_raises(Asset::InvalidDirError) { Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/a.md") }
    assert_raises(Asset::InvalidNameError) { Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/x", name: "a b") }
    assert_raises(Assets::ForbiddenError) { Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "other/notes") }
    assert_raises(Assets::ForbiddenError) { Assets::Move.mutate(actor: actor_for(:other_default), slug: @asset.slug, path: "other/notes") }
    assert_equal "member/notes/hello.md", @asset.reload.location

    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)
    assert_raises(Assets::NotFoundError) { Assets::Move.mutate(actor: @actor, slug: @asset.slug, path: "member/x") }
  end
end
