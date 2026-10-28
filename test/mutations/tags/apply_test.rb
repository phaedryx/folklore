require "test_helper"

class Tags::ApplyTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "")
  end

  test "adds a tag to an asset, normalized to lowercase" do
    Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: " Ruby ")

    assert_equal %w[ruby], @asset.reload.tags.pluck(:name)
  end

  test "writes a tag_added event naming the tag" do
    Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: "ruby")

    event = Event.where(action: "tag_added").last
    assert_equal @asset.id, event.asset_id
    assert_equal "ping", event.actor_agent
    assert_equal({ "tag" => "ruby" }, event.metadata)
  end

  test "raises AlreadyAppliedError when the tag is already on the asset" do
    Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: "ruby")

    assert_raises(Tags::Apply::AlreadyAppliedError) { Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: "RUBY") }
  end

  test "raises NotFoundError for an unknown or deleted slug" do
    assert_raises(Tags::Apply::NotFoundError) { Tags::Apply.mutate(actor: @actor, slug: "00000000", tag: "ruby") }

    @asset.update!(deleted_at: Time.current)
    assert_raises(Tags::Apply::NotFoundError) { Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: "ruby") }
  end

  test "raises ForbiddenError for another member's asset" do
    assert_raises(Tags::Apply::ForbiddenError) { Tags::Apply.mutate(actor: actor_for(:other_default), slug: @asset.slug, tag: "ruby") }
    assert_empty @asset.reload.tags
  end

  test "rejects a blank tag" do
    assert_raises(Tags::Apply::InvalidTagError) { Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: "  ") }
  end
end
