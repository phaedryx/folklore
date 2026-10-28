require "test_helper"

class AssetTest < ActiveSupport::TestCase
  def build(dir:, name:, **attrs)
    Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir:, name:, **attrs)
  end

  test "live and tombstoned partition on deleted_at" do
    live = build(dir: "member/notes", name: "a.md")
    gone = build(dir: "member/notes", name: "b.md", deleted_at: Time.current)

    assert_includes Asset.live, live
    refute_includes Asset.live, gone
    assert_includes Asset.tombstoned, gone
    refute_includes Asset.tombstoned, live
  end

  test "stale and not_stale partition on stale_after; no review date is never stale" do
    overdue = build(dir: "member/notes", name: "a.md", stale_after: Date.yesterday)
    fresh = build(dir: "member/notes", name: "b.md", stale_after: Date.tomorrow)
    unscheduled = build(dir: "member/notes", name: "c.md")

    assert_equal [ overdue ], Asset.stale.to_a
    assert_includes Asset.not_stale, fresh
    assert_includes Asset.not_stale, unscheduled
    assert overdue.stale?
    refute fresh.stale?
    refute unscheduled.stale?
  end

  test "under_dir matches the directory itself and its descendants but not siblings sharing a prefix" do
    exact = build(dir: "a/b", name: "x.md")
    child = build(dir: "a/b/c", name: "x.md")
    sibling = build(dir: "a/bc", name: "x.md")

    found = Asset.under_dir("a/b").to_a

    assert_includes found, exact
    assert_includes found, child
    refute_includes found, sibling
  end

  test "under_dir escapes LIKE wildcards in the prefix" do
    literal = build(dir: "a/b_c", name: "x.md")
    other = build(dir: "a/bxc", name: "x.md")

    found = Asset.under_dir("a/b_c").to_a

    assert_includes found, literal
    refute_includes found, other
  end

  test "tagged_with narrows to assets carrying every tag and returns none for an unknown tag" do
    both = build(dir: "member/notes", name: "a.md")
    one = build(dir: "member/notes", name: "b.md")
    ruby = Tag.create!(name: "ruby")
    rails = Tag.create!(name: "rails")
    AssetTag.create!(asset: both, tag: ruby)
    AssetTag.create!(asset: both, tag: rails)
    AssetTag.create!(asset: one, tag: ruby)

    assert_equal [ both ], Asset.tagged_with("ruby", "Rails ").to_a
    assert_equal [ both, one ].sort_by(&:id), Asset.tagged_with("ruby").sort_by(&:id)
    assert_empty Asset.tagged_with("nope")
  end

  test "generate_slug returns eight characters from the crockford alphabet" do
    slug = Asset.generate_slug

    assert_equal 8, slug.length
    assert_match(/\A[#{Asset::SLUG_CHARS}]{8}\z/, slug)
  end

  test "location joins dir and name; workspace_handle is the first dir segment" do
    asset = build(dir: "member/notes/deep", name: "a.md")

    assert_equal "member/notes/deep/a.md", asset.location
    assert_equal "member", asset.workspace_handle
  end

  test "task? reflects the presence of a tasks row" do
    note = build(dir: "member/notes", name: "a.md")
    task = build(dir: "member/inbox", name: "t.md")
    Task.create!(asset: task)

    refute note.task?
    assert task.task?
  end

  test "status accepts nil, open and done only" do
    asset = build(dir: "member/notes", name: "a.md")

    [ nil, "open", "done" ].each do |status|
      asset.status = status
      assert asset.valid?, "expected #{status.inspect} to be valid"
    end
    asset.status = "in_progress"
    refute asset.valid?
  end

  test "the live unique index rejects a second live asset at one location but allows a tombstoned twin" do
    build(dir: "member/notes", name: "a.md")

    assert_raises(ActiveRecord::RecordNotUnique) { build(dir: "member/notes", name: "a.md") }
    assert_nothing_raised { build(dir: "member/notes", name: "a.md", deleted_at: Time.current) }
  end

  test "content over 1 MiB is rejected by the database" do
    assert_raises(ActiveRecord::StatementInvalid) do
      build(dir: "member/notes", name: "big.md", content: "x" * (1_048_576 + 1))
    end
  end

  test "validate_name! rejects blank, slashes, whitespace and dot names" do
    assert_nothing_raised { Asset.validate_name!("notes.md") }
    [ "", "a/b", "a b", ".", ".." ].each do |name|
      assert_raises(Asset::InvalidNameError, name.inspect) { Asset.validate_name!(name) }
    end
  end

  test "validate_dir! accepts ordinary directories" do
    assert_nothing_raised { Asset.validate_dir!("member") }
    assert_nothing_raised { Asset.validate_dir!("member/notes/sub") }
    assert_nothing_raised { Asset.validate_dir!("member/why-nots") }
  end

  test "validate_dir! rejects blank, leading or trailing slashes, empty segments and dot segments" do
    [ "", "/member", "member/", "member//notes", "member/./x", "member/../other" ].each do |dir|
      assert_raises(Asset::InvalidDirError, dir.inspect) { Asset.validate_dir!(dir) }
    end
  end

  test "validate_dir! rejects a last segment that looks like a filename" do
    error = assert_raises(Asset::InvalidDirError) { Asset.validate_dir!("x/notes.md") }

    assert_match(/looks like a filename/, error.message)
  end

  test "validate_dir! rejects reserved second segments unless allowed" do
    assert_raises(Asset::ReservedDirError) { Asset.validate_dir!("member/state") }
    assert_raises(Asset::ReservedDirError) { Asset.validate_dir!("member/state/ping") }
    assert_raises(Asset::ReservedDirError) { Asset.validate_dir!("member/archive") }
    assert_nothing_raised { Asset.validate_dir!("member/notes/state") }
    assert_nothing_raised { Asset.validate_dir!("member/state/ping", allow_reserved: true) }
  end

  test "parse_stale_after! accepts ISO dates, blanks to nil, and rejects garbage" do
    assert_equal Date.new(2026, 1, 2), Asset.parse_stale_after!("2026-01-02")
    assert_equal Date.new(2026, 1, 2), Asset.parse_stale_after!(Date.new(2026, 1, 2))
    assert_nil Asset.parse_stale_after!(nil)
    assert_nil Asset.parse_stale_after!("  ")
    assert_raises(Asset::InvalidStaleAfterError) { Asset.parse_stale_after!("soon") }
  end
end
