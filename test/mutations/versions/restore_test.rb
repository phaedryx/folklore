require "test_helper"

class Versions::RestoreTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "v1")
    Assets::Update.mutate(actor: @actor, slug: @asset.slug, content: "v2")
    Assets::Update.mutate(actor: @actor, slug: @asset.slug, content: "v3")
    @v1 = @asset.versions.order(:created_at).first
  end

  test "snapshots the head, sets content to the chosen version, and keeps that version" do
    Versions::Restore.mutate(actor: @actor, slug: @asset.slug, version_id: @v1.id)

    @asset.reload
    assert_equal "v1", @asset.content
    assert_equal Digest::SHA256.hexdigest("v1"), @asset.content_sha256
    assert_equal %w[v1 v2 v3], @asset.versions.order(:created_at).map(&:content)
    assert_equal "ping", @asset.updated_by_agent
  end

  test "writes one version_restored event with the source version id" do
    Versions::Restore.mutate(actor: @actor, slug: @asset.slug, version_id: @v1.id)

    events = Event.where(action: "version_restored")
    assert_equal 1, events.count
    assert_equal({ "restored_from_version_id" => @v1.id }, events.first.metadata)
    assert_equal 0, Event.where(action: "asset_updated", created_at: events.first.created_at..).count
  end

  test "restoring the version equal to the head writes no snapshot" do
    head_equal = @asset.versions.order(:created_at).last # "v2"
    Assets::Update.mutate(actor: @actor, slug: @asset.slug, content: "v2")

    assert_no_difference -> { Version.count } do
      Versions::Restore.mutate(actor: @actor, slug: @asset.slug, version_id: head_equal.id)
    end
  end

  test "re-syncs wikilinks from the restored content" do
    target = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "t.md")
    linked = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "l.md", content: "[[#{target.slug}]]")
    Assets::Update.mutate(actor: @actor, slug: linked.slug, content: "no links")
    assert_empty linked.links.reload

    Versions::Restore.mutate(actor: @actor, slug: linked.slug, version_id: linked.versions.first.id)

    assert_equal [ target.id ], linked.links.reload.pluck(:dst_asset_id)
  end

  test "raises NotFoundError for an unknown slug or a version not on this asset" do
    other = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "bye.md", content: "x1")
    Assets::Update.mutate(actor: @actor, slug: other.slug, content: "x2")

    assert_raises(Assets::NotFoundError) { Versions::Restore.mutate(actor: @actor, slug: "00000000", version_id: @v1.id) }
    assert_raises(Versions::NotFoundError) { Versions::Restore.mutate(actor: @actor, slug: @asset.slug, version_id: other.versions.first.id) }
  end

  test "raises NotFoundError for a deleted asset and ForbiddenError for another member" do
    assert_raises(Assets::ForbiddenError) { Versions::Restore.mutate(actor: actor_for(:other_default), slug: @asset.slug, version_id: @v1.id) }

    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)
    assert_raises(Assets::NotFoundError) { Versions::Restore.mutate(actor: @actor, slug: @asset.slug, version_id: @v1.id) }
  end
end
