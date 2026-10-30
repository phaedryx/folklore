require "test_helper"

class Bundles::ImportTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir("bundle-import")
    @bundle = BundleWriter.new(@dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  def import(**args)
    Bundles::Import.mutate(dir: @dir, **args)
  end

  def rejection
    assert_raises(Bundles::Import::RejectedError) { import }
  end

  def table_counts
    [ Asset, Version, Task, AssetTag, Tag, Link, Event ].to_h { |model| [ model.name, model.count ] }
  end

  test "imports assets with their slugs, timestamps, tags, versions and tasks" do
    note = @bundle.asset(name: "note.md", content: "see [[nnnnnnnn]]", tags: %w[why-not search], status: "open",
                         stale_after: Date.new(2026, 12, 1), verified_at: Time.utc(2026, 5, 5, 5, 5, 5, 5))
    @bundle.versions(note[:slug], [
      { content: "v1", content_type: "text/markdown", created_at: Time.utc(2026, 1, 1), actor: "member/ping" },
      { content: "v2", content_type: nil, created_at: Time.utc(2026, 1, 2), actor: "nobody/x" },
      { content: nil, content_type: nil, created_at: Time.utc(2026, 1, 3), actor: "member" }
    ])
    task = @bundle.asset(dir: "member/tasks", name: "do.md",
                         task: { status: "failed", attempts: 1, outcome_note: "no", created_at: Time.utc(2026, 2, 1), updated_at: Time.utc(2026, 2, 2) })
    @bundle.write

    report = import

    assert_equal({ assets: 2, archived: 0, versions: 3, tasks: 1 }, report.counts)
    asset = Asset.find_by!(slug: note[:slug])
    assert_equal [ "member/notes", "note.md", "see [[nnnnnnnn]]" ], [ asset.dir, asset.name, asset.content ]
    assert_equal users(:member), asset.owner
    assert_equal Asset.sha256("see [[nnnnnnnn]]"), asset.content_sha256
    assert_equal %w[search why-not], asset.tags.map(&:name).sort
    assert_equal "open", asset.status
    assert_equal Date.new(2026, 12, 1), asset.stale_after
    assert_equal note[:verified_at], asset.verified_at
    assert_equal note[:created_at], asset.created_at
    assert_equal note[:updated_at], asset.updated_at
    assert_nil asset.created_by_agent

    versions = asset.versions.order(:created_at)
    assert_equal [ "v1", "v2", nil ], versions.map(&:content)
    assert_equal [ users(:member), nil, users(:member) ], versions.map(&:actor_user)
    assert_equal [ "ping", nil, nil ], versions.map(&:actor_agent)

    row = Asset.find_by!(slug: task[:slug]).task
    assert_equal [ "failed", 1, "no" ], [ row.status, row.attempts, row.outcome_note ]
    assert_equal Time.utc(2026, 2, 2), row.updated_at

    events = Event.where(action: "asset_imported")
    assert_equal 2, events.count
    assert_equal [ "member" ], events.map { |e| e.actor_user.handle }.uniq
    assert_equal [ "import" ], events.map(&:actor_agent).uniq

    assert_equal [ { slug: note[:slug], location: "member/notes/note.md", ref: "nnnnnnnn" } ], report.dangling_links
  end

  test "a wikilink to a later asset resolves" do
    first = @bundle.asset(name: "first.md", content: "points at [[zzzzzzzz]]")
    @bundle.asset(slug: "zzzzzzzz", name: "second.md", content: "target")
    @bundle.write

    report = import

    link = Asset.find_by!(slug: first[:slug]).links.sole
    assert_equal Asset.find_by!(slug: "zzzzzzzz"), link.dst_asset
    assert_empty report.dangling_links
  end

  test "a link to an asset already on this instance resolves, and its inbound links stay" do
    existing = Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "here.md", content: "x")
    @bundle.asset(name: "new.md", content: "[[#{existing.slug}]]")
    @bundle.write

    import

    assert_equal existing, Link.sole.dst_asset
  end

  test "live and archived at the same location both import, and the live one stays live" do
    gone = @bundle.asset(name: "same.md", content: "old", deleted_at: Time.utc(2026, 3, 1, 0, 0, 0, 7))
    live = @bundle.asset(name: "same.md", content: "new")
    @bundle.write

    report = import

    assert_equal({ assets: 2, archived: 1, versions: 0, tasks: 0 }, report.counts)
    assert_equal live[:slug], Asset.live.find_by!(dir: "member/notes", name: "same.md").slug
    assert_equal gone[:deleted_at], Asset.find_by!(slug: gone[:slug]).deleted_at
  end

  test "sha mismatch rejects with nothing written" do
    note = @bundle.asset(name: "note.md")
    @bundle.write { |m| m[:assets].first[:sha256] = "0" * 64 }
    before = table_counts

    error = rejection

    assert_match(/#{note[:slug]}.*sha256/, error.errors.join("\n"))
    assert_equal before, table_counts
  end

  test "second import rejects on slug collision and leaves counts unchanged" do
    @bundle.asset(name: "a.md")
    @bundle.asset(name: "b.md")
    @bundle.write
    import
    before = table_counts

    error = rejection

    assert_equal 2, error.errors.grep(/already exists/).size
    assert_equal before, table_counts
  end

  test "a live location already taken here is rejected" do
    Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "a.md", content: "x")
    @bundle.asset(name: "a.md")
    @bundle.write

    assert_match(%r{member/notes/a.md is taken}, rejection.errors.join)
  end

  test "unknown owner handle is rejected" do
    @bundle.asset(owner: "ghost", dir: "ghost/notes", name: "a.md")
    @bundle.write

    assert_match(/owner "ghost"/, rejection.errors.join)
  end

  test "state dir must be <handle>/state/<agent> or <handle>/state/<token>/<agent>" do
    @bundle.asset(dir: "member/state/coordinator", name: "last_session.md")
    @bundle.asset(dir: "member/state/team/ping", name: "last_session.md")
    @bundle.write
    import
    assert Asset.live.exists?(dir: "member/state/coordinator", name: "last_session.md")
    assert Asset.live.exists?(dir: "member/state/team/ping", name: "last_session.md")

    [ "member/state", "member/state/Bad.Agent", "member/state/a/B", "member/state/a/b/c", "other/state/x" ].each do |dir|
      FileUtils.rm_rf(@dir)
      @bundle = BundleWriter.new(@dir)
      @bundle.asset(dir:, name: "last_session.md")
      @bundle.write

      assert_match(/reserved|state/, rejection.errors.join, dir)
    end
  end

  test "an archive dir and a bad name are rejected" do
    @bundle.asset(dir: "member/archive", name: "a.md")
    @bundle.asset(name: "has space.md")
    @bundle.write

    errors = rejection.errors
    assert_equal 2, errors.size, errors.join("\n")
  end

  test "in_progress task is rejected" do
    @bundle.asset(name: "t.md", task: { status: "in_progress", attempts: 0, created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 1) })
    @bundle.write

    assert_match(/in_progress/, rejection.errors.join)
  end

  test "a task with a top-level status is rejected" do
    @bundle.asset(name: "t.md", status: "open", task: { status: "pending", attempts: 0, created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 1) })
    @bundle.write

    assert_match(/status/, rejection.errors.join)
  end

  test "content over the cap is rejected" do
    @bundle.asset(name: "big.md", content: "x" * (Asset::MAX_CONTENT_BYTES + 1))
    @bundle.write

    assert_match(/1 MiB/, rejection.errors.join)
  end

  test "a tag or task note over its length limit is rejected with nothing written" do
    @bundle.asset(name: "a.md", tags: [ "t" * (Tag::MAX_NAME_LENGTH + 1) ])
    @bundle.asset(name: "t.md", task: { status: "done", attempts: 1, outcome_note: "n" * (Task::MAX_NOTE_LENGTH + 1),
                                        created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 1) })
    @bundle.write

    before = table_counts
    errors = rejection.errors.join("\n")
    assert_match(/a\.md: tag is 101 characters, over the 100 character limit/, errors)
    assert_match(/t\.md: task outcome_note is 10001 characters, over the 10000 character limit/, errors)
    assert_equal before, table_counts
  end

  test "an unknown format version is rejected" do
    @bundle.asset(name: "a.md")
    @bundle.write
    path = File.join(@dir, "manifest.json")
    File.write(path, File.read(path).sub('"version": 1', '"version": 2'))

    assert_match(/version 2/, rejection.errors.join)
  end

  test "counts that disagree with the files are rejected" do
    @bundle.asset(name: "a.md")
    @bundle.write(manifest_counts: { assets: 2, archived: 0, versions: 0, tasks: 0 })

    assert_match(/counts.assets is 2 but the bundle has 1/, rejection.errors.join)
  end

  test "an unlisted file, a missing file and versions for an unknown slug are rejected" do
    @bundle.asset(name: "a.md")
    @bundle.versions("nosuch00", [ { content: "x", content_type: nil, created_at: Time.utc(2026, 1, 1), actor: nil } ])
    @bundle.write { |m| m[:assets] << { slug: "missing0", file: "assets/member/notes/missing.md", sha256: nil } }
    @bundle.put("assets/member/notes/stray.md", "---\nslug: stray000\n---\n")

    errors = rejection.errors.join("\n")
    assert_match(/stray.md is not listed/, errors)
    assert_match(/missing.md does not exist/, errors)
    assert_match(/nosuch00/, errors)
  end

  test "a file whose path does not match its front matter is rejected" do
    note = @bundle.asset(name: "a.md")
    @bundle.write
    FileUtils.mv(File.join(@dir, "assets/member/notes/a.md"), File.join(@dir, "assets/member/notes/b.md"))
    File.write(File.join(@dir, "manifest.json"), File.read(File.join(@dir, "manifest.json")).sub("notes/a.md", "notes/b.md"))

    assert_match(/#{note[:slug]}.*should be at assets\/member\/notes\/a.md/, rejection.errors.join)
  end

  test "every problem is reported at once" do
    @bundle.asset(owner: "ghost", dir: "ghost/notes", name: "a.md")
    @bundle.asset(name: "t.md", task: { status: "in_progress", attempts: 0, created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 1) })
    @bundle.write

    errors = rejection.errors
    assert_equal 2, errors.size, errors.join("\n")
  end

  test "dry run writes nothing and reports the same counts" do
    @bundle.asset(name: "a.md", content: "[[qqqqqqqq]]")
    @bundle.asset(name: "gone.md", deleted_at: Time.utc(2026, 1, 3))
    @bundle.write
    before = table_counts

    dry = import(dry_run: true)

    assert_equal before, table_counts
    assert dry.dry_run
    real = import
    assert_equal dry.counts, real.counts
    assert_equal dry.dangling_links, real.dangling_links
    refute real.dry_run
  end

  test "imported assets are searchable" do
    @bundle.asset(name: "a.md", content: "the quokka migrates")
    @bundle.write

    import

    results = Assets::Search.query(query: "quokka", actor: actor_for(:member_default))
    assert_equal [ "a.md" ], results.map(&:name)
  end
end
