require "test_helper"

# Pins Export and Import to each other: whatever one writes, the other reads
# back unchanged.
class Bundles::RoundTripTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @dir = Dir.mktmpdir("bundle-round-trip")
    FileUtils.rm_rf(@dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  def create(name, content, path: "member/notes", tags: [])
    Assets::Create.mutate(actor: @actor, path:, name:, content:, tags:)
  end

  def snapshot
    Asset.preload(:tags, :task, versions: :actor_user).order(:slug).map do |asset|
      {
        slug: asset.slug, owner: asset.owner_id, dir: asset.dir, name: asset.name,
        content: asset.content&.b, content_type: asset.content_type, sha: asset.content_sha256,
        tags: asset.tags.map(&:name).sort, status: asset.status, stale_after: asset.stale_after,
        verified_at: asset.verified_at, created_at: asset.created_at, updated_at: asset.updated_at,
        deleted_at: asset.deleted_at,
        versions: asset.versions.sort_by { |v| [ v.created_at, v.id ] }.map do |v|
          [ v.content, v.content_type, v.created_at, v.actor_user&.handle, v.actor_agent ]
        end,
        task: asset.task&.slice(:status, :attempts, :outcome_note, :created_at, :updated_at),
        # An archived asset's link rows are not exported: backlinks count only
        # live sources, and a restore syncs the links from content again.
        links: asset.deleted_at? ? [] : asset.links.map { |l| [ l.dst_ref, l.dst_asset&.slug ] }.sort
      }
    end
  end

  def wipe
    [ Event, Link, AssetTag, Tag, Version, Task, Asset ].each(&:delete_all)
  end

  test "export then import into an empty database reproduces every asset byte for byte" do
    target = create("target.md", "no newline")
    [ "", "a\r\nb", "ends\n", "---\nfront\n---\n", "é ✓" ].each_with_index do |content, i|
      create("c#{i}.md", content, tags: %w[edge])
    end
    create("nil.md", nil)
    linker = create("linker.md", "see [[#{target.slug}]] and [[qqqqqqqq]]", tags: %w[why-not search])
    Assets::Update.mutate(actor: @actor, slug: linker.slug, content: "see [[#{target.slug}]] and [[qqqqqqqq]] again")
    Assets::Update.mutate(actor: actor_for(:member_default), slug: linker.slug, content: "see [[#{target.slug}]] and [[qqqqqqqq]] twice")
    linker.reload.update!(status: "done", stale_after: Date.new(2027, 1, 1), verified_at: Time.current)
    gone = create("same.md", "archived, linking [[#{target.slug}]]")
    Assets::Delete.mutate(actor: @actor, slug: gone.slug)
    create("same.md", "live")
    Tasks::Add.mutate(actor: @actor, path: "member/tasks", name: "pending.md", content: "do it")
    Tasks::Add.mutate(actor: @actor, path: "member/tasks", name: "done.md").task.update!(status: "done", attempts: 1, outcome_note: "ok")
    Assets::Create.mutate(actor: @actor, path: "member/state/ping", name: "last_session.md", content: "checkpoint", reserved: true)
    Assets::Create.mutate(actor: actor_for(:other_default), path: "other/notes", name: "theirs.md", content: "other")

    expected = snapshot
    export = Bundles::Export.query(dir: @dir)
    wipe

    report = Bundles::Import.mutate(dir: @dir)

    assert_equal export.counts, report.counts
    assert_equal expected, snapshot
    assert_equal [ "qqqqqqqq" ], report.dangling_links.pluck(:ref)
    assert_equal [ linker.slug ], Links::Backlinks.query(asset: Asset.find_by!(slug: target.slug)).map(&:slug)
  end

  test "locations that meet on disk survive the round trip" do
    create("a", "the file", path: "member")
    create("b.md", "inside the directory", path: "member/a")
    create("A.md", "upper")
    create("a.md", "lower")

    expected = snapshot
    Bundles::Export.query(dir: @dir)
    wipe

    Bundles::Import.mutate(dir: @dir)

    assert_equal expected, snapshot
  end
end
