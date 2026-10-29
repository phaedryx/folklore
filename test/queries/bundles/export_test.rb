require "test_helper"

class Bundles::ExportTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @dir = Dir.mktmpdir("bundle-export")
    FileUtils.rm_rf(@dir)
  end

  teardown { FileUtils.rm_rf(@dir) }

  def create(name, path: "member/notes", content: "body", tags: [], actor: @actor)
    Assets::Create.mutate(actor:, path:, name:, content:, tags:)
  end

  def export(**args)
    Bundles::Export.query(dir: @dir, **args)
  end

  def read(relative)
    File.binread(File.join(@dir, relative))
  end

  def manifest
    Bundles::Format.load_manifest(read("manifest.json"))
  end

  test "writes live, archived, task, versioned and nil-content assets with a manifest" do
    note = create("note.md", content: "ends without newline", tags: %w[why-not search])
    note.update!(status: "open", stale_after: Date.new(2026, 12, 1), verified_at: Time.utc(2026, 10, 1, 1, 2, 3, 456))
    Version.create!(asset: note, content: "v1", content_type: "text/markdown", actor_user: users(:member),
                    actor_agent: "ping", created_at: Time.utc(2026, 1, 1))
    Version.create!(asset: note, content: nil, content_type: nil, created_at: Time.utc(2026, 1, 2))
    empty = create("empty.md", content: nil)
    gone = create("gone.md", content: "old")
    Assets::Delete.mutate(actor: @actor, slug: gone.slug)
    task = Tasks::Add.mutate(actor: @actor, path: "member/tasks", name: "do.md", content: "work")
    task.task.update!(status: "done", attempts: 1, outcome_note: "shipped")

    result = export

    assert_equal({ assets: 4, archived: 1, versions: 2, tasks: 1 }, result.counts)
    assert_equal result.counts, manifest[:counts]

    loaded = Bundles::Format.load_asset(read("assets/member/notes/note.md"))
    assert_equal note.slug, loaded[:slug]
    assert_equal "member", loaded[:owner]
    assert_equal "ends without newline", loaded[:content]
    assert_equal %w[search why-not], loaded[:tags]
    assert_equal "open", loaded[:status]
    assert_equal Date.new(2026, 12, 1), loaded[:stale_after]
    assert_equal note.reload.verified_at, loaded[:verified_at]
    assert_equal note.created_at, loaded[:created_at]
    assert_nil loaded[:task]

    assert_nil Bundles::Format.load_asset(read("assets/member/notes/empty.md"))[:content]

    archived = Bundles::Format.load_asset(read("archived/#{gone.slug}/member/notes/gone.md"))
    assert_equal gone.reload.deleted_at, archived[:deleted_at]

    loaded_task = Bundles::Format.load_asset(read("assets/member/tasks/do.md"))[:task]
    assert_equal({ status: "done", attempts: 1, outcome_note: "shipped" }, loaded_task.slice(:status, :attempts, :outcome_note))

    versions = Bundles::Format.load_versions(read("versions/#{note.slug}.jsonl"))
    assert_equal [ "v1", nil ], versions.pluck(:content)
    assert_equal [ "member/ping", nil ], versions.pluck(:actor)
    refute File.exist?(File.join(@dir, "versions/#{empty.slug}.jsonl"))

    entries = manifest[:assets].index_by { |a| a[:slug] }
    assert_equal 4, entries.size
    assert_equal "assets/member/notes/note.md", entries[note.slug][:file]
    assert_equal Digest::SHA256.hexdigest("ends without newline"), entries[note.slug][:sha256]
    assert_nil entries[empty.slug][:sha256]
    assert_equal "archived/#{gone.slug}/member/notes/gone.md", entries[gone.slug][:file]
  end

  test "refuses a non-empty directory" do
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "stray"), "x")

    assert_raises(Bundles::Export::NotEmptyError) { export }
  end

  test "writes into an existing empty directory" do
    FileUtils.mkdir_p(@dir)
    create("a.md")

    assert_equal 1, export.counts[:assets]
  end

  test "live and archived at the same dir/name both export" do
    first = create("same.md", content: "first")
    Assets::Delete.mutate(actor: @actor, slug: first.slug)
    second = create("same.md", content: "second")
    Assets::Delete.mutate(actor: @actor, slug: second.slug)
    live = create("same.md", content: "live")

    export

    assert_equal [ live.slug, "live" ],
                 Bundles::Format.load_asset(read("assets/member/notes/same.md")).values_at(:slug, :content)
    assert_equal "first", Bundles::Format.load_asset(read("archived/#{first.slug}/member/notes/same.md"))[:content]
    assert_equal "second", Bundles::Format.load_asset(read("archived/#{second.slug}/member/notes/same.md"))[:content]
  end

  test "handle limits the export to one workspace" do
    create("mine.md")
    create("theirs.md", path: "other/notes", actor: actor_for(:other_default))

    result = export(handle: "member")

    assert_equal 1, result.counts[:assets]
    assert_equal [ "assets/member/notes/mine.md" ], manifest[:assets].pluck(:file)
  end

  test "query count does not grow with the number of assets" do
    seed = ->(n) {
      n.times do |i|
        asset = create("n#{i}-#{SecureRandom.hex(2)}.md", tags: %w[a b])
        Version.create!(asset:, content: "old", actor_user: users(:member), created_at: Time.current)
      end
      Tasks::Add.mutate(actor: @actor, path: "member/tasks", name: "t#{SecureRandom.hex(2)}.md")
    }

    seed.call(2)
    small = count_queries { export }
    FileUtils.rm_rf(@dir)
    seed.call(8)
    large = count_queries { export }

    assert_equal small, large
  end
end
