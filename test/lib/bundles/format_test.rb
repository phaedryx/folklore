require "test_helper"

class Bundles::FormatTest < ActiveSupport::TestCase
  def attrs(**overrides)
    {
      slug: "abcd1234",
      owner: "member",
      dir: "member/notes",
      name: "x.md",
      content_type: "text/markdown",
      content: "hello",
      tags: %w[why-not search],
      status: "open",
      stale_after: Date.new(2026, 12, 1),
      verified_at: Time.utc(2026, 10, 1, 12, 0, 0, 123_456),
      created_at: Time.utc(2026, 9, 1, 8, 30, 0, 1),
      updated_at: Time.utc(2026, 9, 2, 8, 30, 0, 999_999)
    }.merge(overrides)
  end

  test "round-trips content byte for byte" do
    [ "", "x", "a\r\nb", "ends\n", "no newline", "---\nfront\n---\n", "é ✓" ].each do |content|
      h = attrs(content:)
      loaded = Bundles::Format.load_asset(Bundles::Format.dump_asset(h))

      assert_equal h[:content], loaded[:content], "content #{content.inspect}"
      assert_equal h[:content].b, loaded[:content].b, "bytes of #{content.inspect}"
      assert_equal Encoding::UTF_8, loaded[:content].encoding
    end
  end

  test "round-trips the front matter" do
    loaded = Bundles::Format.load_asset(Bundles::Format.dump_asset(attrs))

    assert_equal attrs.except(:content), loaded.except(:content, :content_nil, :deleted_at, :task)
    assert_nil loaded[:deleted_at]
    assert_nil loaded[:task]
  end

  test "times keep their microseconds" do
    text = Bundles::Format.dump_asset(attrs)

    assert_includes text, "verified_at: '2026-10-01T12:00:00.123456Z'"
    assert_equal 1, Bundles::Format.load_asset(text)[:created_at].usec
  end

  test "nil content survives as nil" do
    text = Bundles::Format.dump_asset(attrs(content: nil))

    assert_includes text, "content_nil: true"
    assert text.end_with?("---\n")
    assert_nil Bundles::Format.load_asset(text)[:content]
  end

  test "a task block and deleted_at round-trip" do
    task = { status: "pending", attempts: 0, outcome_note: "a\n---\nb",
             created_at: Time.utc(2026, 1, 1), updated_at: Time.utc(2026, 1, 2) }
    h = attrs(status: nil, task:, deleted_at: Time.utc(2026, 3, 3, 3, 3, 3, 3))
    loaded = Bundles::Format.load_asset(Bundles::Format.dump_asset(h))

    assert_equal task, loaded[:task]
    assert_equal h[:deleted_at], loaded[:deleted_at]
  end

  test "loads leniently: missing optional keys read as null" do
    loaded = Bundles::Format.load_asset("---\nslug: abcd1234\nowner: member\ndir: member\nname: x.md\n---\nbody")

    assert_equal "body", loaded[:content]
    assert_equal [], loaded[:tags]
    assert_nil loaded[:status]
    assert_nil loaded[:stale_after]
    assert_nil loaded[:task]
  end

  test "rejects a file without front matter, naming the file" do
    error = assert_raises(Bundles::Format::InvalidError) do
      Bundles::Format.load_asset("just text", file: "assets/member/x.md")
    end
    assert_match "assets/member/x.md", error.message
  end

  test "rejects unterminated front matter and a non-hash front matter" do
    assert_raises(Bundles::Format::InvalidError) { Bundles::Format.load_asset("---\nslug: x\n") }
    assert_raises(Bundles::Format::InvalidError) { Bundles::Format.load_asset("---\n- a\n---\n") }
  end

  test "rejects an unparseable time" do
    assert_raises(Bundles::Format::InvalidError) do
      Bundles::Format.load_asset("---\nslug: x\ncreated_at: yesterday\n---\n")
    end
  end

  test "rejects content alongside content_nil" do
    assert_raises(Bundles::Format::InvalidError) do
      Bundles::Format.load_asset("---\nslug: x\ncontent_nil: true\n---\nbody")
    end
  end

  test "rejects unknown format version" do
    manifest = { format: "folklore-bundle", version: 2, exported_at: "x", counts: {}, assets: [] }.to_json

    error = assert_raises(Bundles::Format::InvalidError) { Bundles::Format.load_manifest(manifest) }
    assert_match(/version 2/, error.message)
  end

  test "rejects a manifest of another format" do
    manifest = { format: "other", version: 1 }.to_json

    assert_raises(Bundles::Format::InvalidError) { Bundles::Format.load_manifest(manifest) }
    assert_raises(Bundles::Format::InvalidError) { Bundles::Format.load_manifest("not json") }
  end

  test "manifest round-trips" do
    manifest = Bundles::Format.dump_manifest(
      exported_at: Time.utc(2026, 10, 28),
      counts: { assets: 1, archived: 0, versions: 0, tasks: 0 },
      assets: [ { slug: "abcd1234", file: "assets/member/x.md", sha256: nil } ]
    )
    loaded = Bundles::Format.load_manifest(manifest)

    assert_equal "folklore-bundle", loaded[:format]
    assert_equal 1, loaded[:version]
    assert_equal({ assets: 1, archived: 0, versions: 0, tasks: 0 }, loaded[:counts])
    assert_equal [ { slug: "abcd1234", file: "assets/member/x.md", sha256: nil } ], loaded[:assets]
  end

  test "asset_path puts every asset under its slug" do
    assert_equal "assets/abcd1234/member/notes/x.md",
                 Bundles::Format.asset_path(dir: "member/notes", name: "x.md", slug: "abcd1234", archived: false)
    assert_equal "archived/abcd1234/member/notes/x.md",
                 Bundles::Format.asset_path(dir: "member/notes", name: "x.md", slug: "abcd1234", archived: true)
  end

  test "versions round-trip as json lines" do
    rows = [
      { content: "a\r\n", content_type: "text/markdown", created_at: Time.utc(2026, 1, 1, 0, 0, 0, 5), actor: "member/ping" },
      { content: nil, content_type: nil, created_at: Time.utc(2026, 1, 2), actor: nil }
    ]
    text = Bundles::Format.dump_versions(rows)

    assert_equal 2, text.lines.size
    assert_equal rows, Bundles::Format.load_versions(text)
    assert_equal [], Bundles::Format.load_versions("")
  end
end
