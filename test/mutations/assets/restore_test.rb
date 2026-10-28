require "test_helper"

class Assets::RestoreTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "hi")
    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)
  end

  test "clears deleted_at, stamps the actor, and writes an asset_restored event" do
    Assets::Restore.mutate(actor: actor_for(:member_default, agent: "pong"), slug: @asset.slug)

    @asset.reload
    assert_nil @asset.deleted_at
    assert_equal "pong", @asset.updated_by_agent
    assert_equal @asset.id, Event.where(action: "asset_restored").last.asset_id
  end

  test "raises NotFoundError for an unknown slug" do
    assert_raises(Assets::NotFoundError) { Assets::Restore.mutate(actor: @actor, slug: "00000000") }
  end

  test "raises NotDeletedError for a live asset" do
    Assets::Restore.mutate(actor: @actor, slug: @asset.slug)

    assert_raises(Assets::NotDeletedError) { Assets::Restore.mutate(actor: @actor, slug: @asset.slug) }
  end

  test "raises ForbiddenError for another member" do
    assert_raises(Assets::ForbiddenError) { Assets::Restore.mutate(actor: actor_for(:other_default), slug: @asset.slug) }

    assert_not_nil @asset.reload.deleted_at
  end

  test "raises NameTakenError when a live asset now occupies the location" do
    Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "v2")

    assert_raises(Assets::NameTakenError) { Assets::Restore.mutate(actor: @actor, slug: @asset.slug) }
    assert_not_nil @asset.reload.deleted_at
  end
end
