require "test_helper"

class Links::SyncTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def create(name, content = "")
    Assets::Create.mutate(actor: @actor, path: "member/notes", name:, content:)
  end

  def links_of(asset)
    asset.links.order(:dst_ref).map { |l| [ l.dst_ref, l.dst_asset_id, l.kind ] }
  end

  test "a content write stores one wikilink row per referenced slug, resolved when the target is live" do
    target = create("target.md")
    source = create("source.md", "see [[#{target.slug}]] and [[zzzzzzzz]]")

    assert_equal [ [ target.slug, target.id, "wikilink" ], [ "zzzzzzzz", nil, "wikilink" ] ], links_of(source)
  end

  test "an update replaces the link set: adds new refs, drops removed ones, keeps the rest" do
    a = create("a.md")
    b = create("b.md")
    source = create("source.md", "[[#{a.slug}]]")
    kept = source.links.first

    Assets::Update.mutate(actor: @actor, slug: source.slug, content: "[[#{a.slug}]] [[#{b.slug}]]")
    assert_equal [ a.slug, b.slug ].sort, source.links.pluck(:dst_ref).sort
    assert Link.exists?(kept.id), "an unchanged link row is kept, not rewritten"

    Assets::Update.mutate(actor: @actor, slug: source.slug, content: "[[#{b.slug}]]")
    assert_equal [ b.slug ], source.links.pluck(:dst_ref)
  end

  test "a dangling link neither breaks the write nor is dropped" do
    source = create("source.md", "[[zzzzzzzz]]")

    assert_equal [ [ "zzzzzzzz", nil, "wikilink" ] ], links_of(source)
  end

  test "a link to a tombstoned asset is dangling until the target is restored" do
    target = create("target.md")
    Assets::Delete.mutate(actor: @actor, slug: target.slug)
    source = create("source.md", "[[#{target.slug}]]")
    assert_nil source.links.first.dst_asset_id

    Assets::Restore.mutate(actor: @actor, slug: target.slug)

    assert_equal target.id, source.links.first.reload.dst_asset_id
    assert_equal [ source ], Links::Backlinks.query(asset: target).to_a
  end

  test "deleting a target unresolves its inbound links" do
    target = create("target.md")
    source = create("source.md", "[[#{target.slug}]]")

    Assets::Delete.mutate(actor: @actor, slug: target.slug)

    assert_nil source.links.first.reload.dst_asset_id
    assert_equal target.slug, source.links.first.dst_ref
  end

  test "backlinks exclude tombstoned sources and unresolved links" do
    target = create("target.md")
    live = create("live.md", "[[#{target.slug}]]")
    gone = create("gone.md", "[[#{target.slug}]]")
    Assets::Delete.mutate(actor: @actor, slug: gone.slug)
    dangling = create("dangling.md", "[[zzzzzzzz]]")

    assert_equal [ live ], Links::Backlinks.query(asset: target).to_a
    assert_equal [ [ "zzzzzzzz", nil ] ], dangling.links.pluck(:dst_ref, :dst_asset_id)
  end

  test "syncing is idempotent" do
    target = create("target.md")
    source = create("source.md", "[[#{target.slug}]]")

    assert_no_difference -> { Link.count } do
      Links::Sync.mutate(asset: source.reload)
      Links::Sync.mutate(asset: source.reload)
    end
  end
end
