require "test_helper"

class Tags::RemoveTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "", tags: %w[ruby rails])
  end

  test "removes a tag from an asset" do
    Tags::Remove.mutate(actor: @actor, slug: @asset.slug, tag: "Ruby")

    assert_equal %w[rails], @asset.reload.tags.pluck(:name)
    assert Tag.exists?(name: "ruby"), "the tag itself survives"
  end

  test "writes a tag_removed event naming the tag" do
    Tags::Remove.mutate(actor: @actor, slug: @asset.slug, tag: "ruby")

    event = Event.where(action: "tag_removed").last
    assert_equal @asset.id, event.asset_id
    assert_equal({ "tag" => "ruby" }, event.metadata)
  end

  test "reports whether anything changed, and a tag not on the asset writes nothing" do
    version = @asset.reload.lock_version
    events = Event.count

    result = Tags::Remove.mutate(actor: @actor, slug: @asset.slug, tag: "python")

    refute result.changed
    assert_equal @asset, result.asset
    assert_equal version, @asset.reload.lock_version
    assert_equal events, Event.count
    assert Tags::Remove.mutate(actor: @actor, slug: @asset.slug, tag: "ruby").changed
  end

  test "raises NotFoundError for an unknown slug" do
    assert_raises(Tags::Remove::NotFoundError) { Tags::Remove.mutate(actor: @actor, slug: "00000000", tag: "ruby") }
  end

  test "raises ForbiddenError for another member's asset" do
    assert_raises(Tags::Remove::ForbiddenError) { Tags::Remove.mutate(actor: actor_for(:other_default), slug: @asset.slug, tag: "ruby") }
    assert_equal 2, @asset.reload.tags.count
  end
end
