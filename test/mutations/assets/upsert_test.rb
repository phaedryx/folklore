require "test_helper"

class Assets::UpsertTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def upsert(**args)
    Assets::Upsert.mutate(**{ actor: @actor, path: "member/notes", name: "u.md" }.merge(args))
  end

  test "creates when nothing lives at dir + name, with tags" do
    result = upsert(content: "first", tags: %w[shell])

    assert result.created
    assert_equal "first", result.asset.content
    assert_equal "member/notes", result.asset.dir
    assert_equal %w[shell], result.asset.tags.pluck(:name)
  end

  test "updates the live asset at dir + name, snapshotting a version and replacing tags" do
    existing = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "u.md", content: "v1", tags: %w[shell])

    result = upsert(content: "v2", tags: %w[ruby])

    refute result.created
    assert_equal existing.id, result.asset.id
    assert_equal "v2", existing.reload.content
    assert_equal [ "v1" ], existing.versions.map(&:content)
    assert_equal %w[ruby], existing.tags.pluck(:name)
  end

  test "an upsert that matches what is stored returns the asset and writes nothing" do
    existing = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "u.md", content: "same", tags: %w[shell])

    result = assert_no_difference -> { Event.count } do
      upsert(content: "same", tags: %w[shell])
    end

    refute result.created
    assert_equal existing.id, result.asset.id
    assert_equal 0, existing.reload.lock_version
    assert_empty existing.versions
  end

  test "tags: nil on update leaves tags alone" do
    Assets::Create.mutate(actor: @actor, path: "member/notes", name: "u.md", content: "v1", tags: %w[shell])

    result = upsert(content: "v2")

    assert_equal %w[shell], result.asset.tags.pluck(:name)
  end

  test "a deleted asset at the same location is not matched" do
    deleted = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "u.md", content: "old")
    Assets::Delete.mutate(actor: @actor, slug: deleted.slug)

    result = upsert(content: "new")

    assert result.created
    assert_not_equal deleted.id, result.asset.id
  end

  test "refuses another member's workspace whether or not the asset exists" do
    assert_raises(Assets::ForbiddenError) { upsert(path: "other/notes", content: "x") }

    Assets::Create.mutate(actor: actor_for(:other_default), path: "other/notes", name: "u.md", content: "theirs")
    assert_raises(Assets::ForbiddenError) { upsert(path: "other/notes", content: "x") }
  end

  test "reserved: true passes through to create" do
    result = upsert(path: "member/state/ping", name: "last_session.md", content: "x", reserved: true)

    assert result.created
    assert_equal "member/state/ping", result.asset.dir
  end
end
