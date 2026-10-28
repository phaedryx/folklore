require "test_helper"

class Assets::DeleteTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "hi")
  end

  test "tombstones the asset, stamps the actor, and writes an asset_deleted event" do
    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)

    @asset.reload
    assert_not_nil @asset.deleted_at
    assert_equal "ping", @asset.updated_by_agent
    event = Event.where(action: "asset_deleted").last
    assert_equal @asset.id, event.asset_id
    assert_equal "ping", event.actor_agent
  end

  test "frees the name for a new asset" do
    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)

    assert_nothing_raised { Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md") }
  end

  test "raises NotFoundError for an unknown slug" do
    assert_raises(Assets::NotFoundError) { Assets::Delete.mutate(actor: @actor, slug: "00000000") }
  end

  test "raises AlreadyDeletedError the second time" do
    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)

    assert_raises(Assets::AlreadyDeletedError) { Assets::Delete.mutate(actor: @actor, slug: @asset.slug) }
  end

  test "raises ForbiddenError for another member and writes nothing" do
    assert_raises(Assets::ForbiddenError) { Assets::Delete.mutate(actor: actor_for(:other_default), slug: @asset.slug) }

    assert_nil @asset.reload.deleted_at
    assert_nil Event.find_by(action: "asset_deleted")
  end
end
