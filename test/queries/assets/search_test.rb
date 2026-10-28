require "test_helper"

class Assets::SearchTest < ActiveSupport::TestCase
  def build(name, content: "", dir: "member/notes", tags: [], **attrs)
    asset = Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir:, name:, content:, **attrs)
    tags.each { |tag| AssetTag.create!(asset:, tag: Tag.find_or_create_by!(name: tag)) }
    asset
  end

  # Replaces the asset's content, snapshotting what it had, the way a content update does.
  def rewrite(asset, content)
    Version.create!(asset:, content: asset.content, content_type: asset.content_type)
    asset.update!(content:)
  end

  test "returns assets matching content" do
    build("a.md", content: "ruby on rails")
    build("b.md", content: "python django")

    results = Assets::Search.query(query: "rails")

    assert_equal %w[a.md], results.map(&:name)
  end

  test "returns assets matching name" do
    build("deployment-guide.md")
    build("onboarding.md")

    results = Assets::Search.query(query: "deploy")

    assert_equal %w[deployment-guide.md], results.map(&:name)
  end

  test "excludes deleted assets" do
    build("gone.md", content: "ruby on rails", deleted_at: Time.current)
    build("present.md", content: "ruby on rails")

    results = Assets::Search.query(query: "rails")

    assert_equal %w[present.md], results.map(&:name)
  end

  test "scopes results to a given path" do
    build("here.md", content: "ruby on rails")
    build("elsewhere.md", content: "ruby on rails", dir: "member/scripts")

    results = Assets::Search.query(query: "rails", path: "member/notes")

    assert_equal %w[here.md], results.map(&:name)
  end

  test "path scope covers the directory and everything below it, not a sibling with the same prefix" do
    build("top.md", content: "ruby on rails", dir: "member/notes")
    build("nested.md", content: "ruby on rails", dir: "member/notes/deep")
    build("sibling.md", content: "ruby on rails", dir: "member/notes-archive")

    results = Assets::Search.query(query: "rails", path: "member/notes", sort: "name")

    assert_equal %w[nested.md top.md], results.map(&:name)
  end

  test "tag filter returns assets with that tag" do
    build("a.md", tags: %w[shell])
    build("b.md", tags: %w[ruby])

    results = Assets::Search.query(query: "", tags: %w[shell])

    assert_equal %w[a.md], results.map(&:name)
  end

  test "tag intersection requires all tags to be present" do
    build("both.md", tags: %w[shell onboarding])
    build("one.md", tags: %w[shell])
    build("none.md")

    results = Assets::Search.query(query: "", tags: %w[shell onboarding])

    assert_equal %w[both.md], results.map(&:name)
  end

  test "unknown tag returns empty results" do
    build("a.md", content: "rails", tags: %w[shell])

    results = Assets::Search.query(query: "rails", tags: %w[nonexistent])

    assert_equal 0, results.count
  end

  test "combined query and tag filter" do
    build("a.md", content: "ruby on rails", tags: %w[shell])
    build("b.md", content: "ruby on rails", tags: %w[python])
    build("c.md", content: "python django", tags: %w[shell])

    results = Assets::Search.query(query: "rails", tags: %w[shell])

    assert_equal %w[a.md], results.map(&:name)
  end

  test "status filter finds done notes" do
    build("done-note.md", content: "rails", status: "done")
    build("plain-note.md", content: "rails")

    results = Assets::Search.query(query: "rails", status: "done")

    assert_equal %w[done-note.md], results.map(&:name)
  end

  test "status also matches a task's lifecycle state, as the single status field did" do
    pending = build("pending-task.md", content: "rails work")
    done_task = build("done-task.md", content: "rails work")
    build("done-note.md", content: "rails work", status: "done")
    build("open-note.md", content: "rails work", status: "open")
    Task.create!(asset: pending, status: "pending")
    Task.create!(asset: done_task, status: "done")

    assert_equal %w[pending-task.md], Assets::Search.query(query: "rails", status: "pending").map(&:name)
    assert_equal %w[done-note.md done-task.md], Assets::Search.query(query: "rails", status: "done").map(&:name).sort
  end

  test "task_status filter restricts to tasks in that lifecycle state" do
    pending = build("pending-task.md", content: "rails work")
    done = build("done-task.md", content: "rails work")
    build("plain-note.md", content: "rails work")
    Task.create!(asset: pending, status: "pending")
    Task.create!(asset: done, status: "done")

    results = Assets::Search.query(query: "rails", task_status: "pending")

    assert_equal %w[pending-task.md], results.map(&:name)
  end

  test "task_status filter composes with the other filters" do
    tagged = build("tagged.md", content: "rails work", tags: %w[urgent])
    untagged = build("untagged.md", content: "rails work")
    Task.create!(asset: tagged, status: "pending")
    Task.create!(asset: untagged, status: "pending")

    results = Assets::Search.query(query: "rails", task_status: "pending", tags: %w[urgent])

    assert_equal %w[tagged.md], results.map(&:name)
  end

  test "exclude_tags removes assets having any of those tags" do
    build("keep.md", content: "rails", tags: %w[shell])
    build("drop.md", content: "rails", tags: %w[shell done])

    results = Assets::Search.query(query: "rails", exclude_tags: %w[done])

    assert_equal %w[keep.md], results.map(&:name)
  end

  test "exclude_tags combines with include tags for tagged-X-but-not-done queries" do
    build("todo.md", content: "rails", tags: %w[review])
    build("finished.md", content: "rails", tags: %w[review done])

    results = Assets::Search.query(query: "rails", tags: %w[review], exclude_tags: %w[done])

    assert_equal %w[todo.md], results.map(&:name)
  end

  test "exclude_tags with unknown tag is a no-op" do
    build("a.md", content: "rails", tags: %w[shell])

    results = Assets::Search.query(query: "rails", exclude_tags: %w[nonexistent])

    assert_equal %w[a.md], results.map(&:name)
  end

  test "sort by name orders results alphabetically" do
    build("c.md", content: "rails")
    build("a.md", content: "rails")
    build("b.md", content: "rails")

    results = Assets::Search.query(query: "rails", sort: "name")

    assert_equal %w[a.md b.md c.md], results.map(&:name)
  end

  test "unknown sort leaves the default ordering intact" do
    build("a.md", content: "rails")

    results = Assets::Search.query(query: "rails", sort: "; drop table")

    assert_equal %w[a.md], results.map(&:name)
  end

  test "limit caps and offset skips results" do
    build("a.md", content: "rails")
    build("b.md", content: "rails")
    build("c.md", content: "rails")

    page = Assets::Search.query(query: "rails", sort: "name", limit: 1, offset: 1)

    assert_equal %w[b.md], page.map(&:name)
  end

  test "stale filter returns only assets whose review date has passed" do
    build("overdue.md", content: "rails", stale_after: Date.current - 1)
    build("upcoming.md", content: "rails", stale_after: Date.current + 1)

    results = Assets::Search.query(query: "rails", stale: true)

    assert_equal %w[overdue.md], results.map(&:name)
  end

  test "stale filter excludes assets that never set a review date" do
    build("undated.md", content: "rails")

    results = Assets::Search.query(query: "rails", stale: true)

    assert_empty results
  end

  test "an asset is not stale on its stale_after date, only after it" do
    build("today.md", content: "rails", stale_after: Date.current)

    assert_empty Assets::Search.query(query: "rails", stale: true)
  end

  test "stale: false returns everything not overdue, including undated assets" do
    build("overdue.md", content: "rails", stale_after: Date.current - 1)
    build("undated.md", content: "rails")

    results = Assets::Search.query(query: "rails", stale: false, sort: "name")

    assert_equal %w[undated.md], results.map(&:name)
  end

  test "stale: false composes with a path scope" do
    build("overdue.md", content: "rails", stale_after: Date.current - 1)
    build("undated.md", content: "rails")
    build("other.md", content: "rails", dir: "member/elsewhere")

    results = Assets::Search.query(query: "rails", path: "member/notes", stale: false)

    assert_equal %w[undated.md], results.map(&:name)
  end

  test "stale: false composes with a tag filter" do
    build("overdue.md", content: "rails", tags: %w[shell], stale_after: Date.current - 1)
    build("undated.md", content: "rails", tags: %w[shell])
    build("untagged.md", content: "rails")

    results = Assets::Search.query(query: "rails", tags: %w[shell], stale: false)

    assert_equal %w[undated.md], results.map(&:name)
  end

  test "stale: true composes with a path scope" do
    build("here.md", content: "rails", stale_after: Date.current - 1)
    build("there.md", content: "rails", dir: "member/elsewhere", stale_after: Date.current - 1)

    results = Assets::Search.query(query: "rails", path: "member/notes", stale: true)

    assert_equal %w[here.md], results.map(&:name)
  end

  test "omitting stale leaves the result set unfiltered" do
    build("overdue.md", content: "rails", stale_after: Date.current - 1)
    build("undated.md", content: "rails")

    results = Assets::Search.query(query: "rails", sort: "name")

    assert_equal %w[overdue.md undated.md], results.map(&:name)
  end

  test "matches a stemmed variant of a word in the content" do
    build("a.md", content: "we decided quickly")
    build("b.md", content: "python django")

    results = Assets::Search.query(query: "decide")

    assert_equal %w[a.md], results.map(&:name)
  end

  test "ignores stopwords so a natural-language question still matches" do
    build("a.md", content: "embeddings are cached")
    build("b.md", content: "python django")

    results = Assets::Search.query(query: "what about embeddings")

    assert_equal %w[a.md], results.map(&:name)
  end

  # A pure-name match and a pure-content match each lead one fused list and trail the
  # other, so they tie on score. The tie breaks toward the name.
  test "ranks a name match above a content-only match" do
    build("buried.md", content: "a note mentioning rails once")
    build("rails.md", content: "unrelated filler text")

    results = Assets::Search.query(query: "rails")

    assert_equal %w[rails.md buried.md], results.map(&:name)
  end

  # Guards the argument order of word_similarity(q, name), which is asymmetric.
  # Flipped, "notes.md" scores 0.67 against this query instead of 0.30 and matches.
  test "does not match a short name that is merely contained in a long query" do
    build("a.md", content: "rails upgrade notes")
    build("notes.md", content: "python django")

    results = Assets::Search.query(query: "rails upgrade notes")

    assert_equal %w[a.md], results.map(&:name)
  end

  test "a query-less search still returns every match now that relevance ordering exists" do
    build("a.md", tags: %w[shell])
    build("b.md", tags: %w[shell])
    build("c.md", tags: %w[shell])

    results = Assets::Search.query(query: "", tags: %w[shell])

    assert_equal %w[a.md b.md c.md], results.map(&:name).sort
  end

  test "falls back to matching any term when requiring all of them finds nothing" do
    build("a.md", content: "we chose a cavoodle for the family dog breed")
    build("b.md", content: "python django")

    results = Assets::Search.query(query: "what dog breed did we pick")

    assert_equal %w[a.md], results.map(&:name)
  end

  test "does not widen to any-term matching while all-term matching still finds something" do
    build("a.md", content: "rails upgrade guide")
    build("b.md", content: "rails deployment")

    results = Assets::Search.query(query: "rails upgrade")

    assert_equal %w[a.md], results.map(&:name)
  end

  # An all-terms hit anywhere in the corpus suppresses every any-term-only candidate,
  # even one that would have outscored it on the widened query.
  test "a single all-terms hit keeps any-term candidates out entirely" do
    build("exact.md", content: "the cavoodle is a family dog breed")
    build("loud.md", content: "dog dog dog dog dog breed breed breed breed")
    build("quiet.md", content: "family family family family")

    results = Assets::Search.query(query: "cavoodle breed")

    assert_equal %w[exact.md], results.map(&:name)
  end

  # websearch_to_tsquery turns "-cluster" into !'cluster'. Rewriting & to | would make
  # that "anything without cluster", which is the whole corpus. Negated queries stay strict.
  test "a negated query is not widened into everything but the negated term" do
    build("a.md", content: "kubernetes cluster")
    build("b.md", content: "python django")
    build("c.md", content: "ruby on rails")

    results = Assets::Search.query(query: "kubernetes -cluster")

    assert_empty results
  end

  test "a negated query still finds what matches it strictly" do
    build("a.md", content: "kubernetes cluster")
    build("b.md", content: "kubernetes helm chart")

    results = Assets::Search.query(query: "kubernetes -cluster")

    assert_equal %w[b.md], results.map(&:name)
  end

  test "widening respects the other filters" do
    build("tagged.md", content: "cavoodle family dog", tags: %w[pets])
    build("untagged.md", content: "cavoodle family dog")

    results = Assets::Search.query(query: "what dog breed did we pick", tags: %w[pets])

    assert_equal %w[tagged.md], results.map(&:name)
  end

  test "include_versions finds an asset by content it used to have" do
    note = build("a.md", content: "we chose postgres")
    rewrite(note, "we chose sqlite")

    results = Assets::Search.query(query: "postgres", include_versions: true)

    assert_equal %w[a.md], results.map(&:name)
  end

  test "displaced content stays invisible without include_versions" do
    note = build("a.md", content: "we chose postgres")
    rewrite(note, "we chose sqlite")

    assert_empty Assets::Search.query(query: "postgres")
  end

  test "include_versions returns an asset once however many versions matched" do
    note = build("a.md", content: "postgres one")
    rewrite(note, "postgres two")
    rewrite(note, "sqlite three")

    results = Assets::Search.query(query: "postgres", include_versions: true)

    assert_equal 1, results.count
    assert_equal %w[a.md], results.map(&:name)
  end

  test "include_versions still respects the other filters" do
    tagged = build("tagged.md", content: "we chose postgres", tags: %w[db])
    untagged = build("untagged.md", content: "we chose postgres")
    rewrite(tagged, "moved on")
    rewrite(untagged, "moved on")

    results = Assets::Search.query(query: "postgres", tags: %w[db], include_versions: true)

    assert_equal %w[tagged.md], results.map(&:name)
  end

  # Relevance scores current content only, so an asset that merely used to say the word
  # must not outrank one that still does.
  test "a version-only match ranks below an asset whose current content matches" do
    build("live.md", content: "postgres is still the choice")
    displaced = build("old.md", content: "postgres was the choice")
    rewrite(displaced, "we moved on")

    results = Assets::Search.query(query: "postgres", include_versions: true)

    assert_equal %w[live.md old.md], results.map(&:name)
  end

  test "include_versions does not resurrect a deleted asset" do
    note = build("gone.md", content: "we chose postgres")
    rewrite(note, "moved on")
    note.update!(deleted_at: Time.current)

    assert_empty Assets::Search.query(query: "postgres", include_versions: true)
  end

  # The relevance join fans out over two ranked lists and regroups by asset. These two
  # rank in opposite orders — rails.md leads on name, verbose.md on content — so each
  # appears at a different position in each list. If the regrouping were ever dropped,
  # both would come back twice.
  test "an asset ranked differently by name and by content is returned once" do
    build("rails.md", content: "rails once")
    build("verbose.md", content: "rails rails rails")

    results = Assets::Search.query(query: "rails")

    assert_equal %w[rails.md verbose.md], results.map(&:name)
  end

  # Three assets, two lists. rails.md leads on name but trails on content; b.md is second on
  # name (by id, both b and c score zero) and first on content. Their fused scores are
  # 1/61 + 1/63 against 1/62 + 1/61, so b.md wins: the sum of both ranks decides, not
  # either list alone.
  test "fuses the content rank with the name rank" do
    build("rails.md", content: "rails once")
    build("b.md", content: "rails rails rails rails rails")
    build("c.md", content: "rails rails")

    results = Assets::Search.query(query: "rails")

    assert_equal %w[b.md rails.md c.md], results.map(&:name)
  end

  test "a limit outside 1..500 or a negative offset is refused" do
    build("a.md", content: "rails")

    assert_raises(Assets::Search::InvalidArgumentError) { Assets::Search.query(query: "rails", limit: 0) }
    assert_raises(Assets::Search::InvalidArgumentError) { Assets::Search.query(query: "rails", limit: 501) }
    assert_raises(Assets::Search::InvalidArgumentError) { Assets::Search.query(query: "rails", offset: -1) }
    assert_equal %w[a.md], Assets::Search.query(query: "rails", limit: 500, offset: 0).map(&:name)
  end

  # Real miss from the eval set: the filename says everything the query does, in a
  # different order and with the PR numbers glued on, and it scored 0.475.
  test "matches a name that restates the query in a different order" do
    build("alias-reads-pr1-pr2-split.md")
    build("onboarding.md")

    results = Assets::Search.query(query: "splitting alias reads across two PRs")

    assert_equal %w[alias-reads-pr1-pr2-split.md], results.map(&:name)
  end

  # The threshold sits at 0.45: 0.475 is admitted above, and 0.41 is not.
  test "rejects a name whose similarity falls just under the threshold" do
    build("employment.md")
    build("deploying-guides.md")

    results = Assets::Search.query(query: "deployment guide")

    assert_equal %w[deploying-guides.md], results.map(&:name)
  end

  test "matches a misspelled name" do
    build("deployment-guide.md")
    build("onboarding.md")

    results = Assets::Search.query(query: "deploymnet")

    assert_equal %w[deployment-guide.md], results.map(&:name)
  end
end
