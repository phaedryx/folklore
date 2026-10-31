require "test_helper"

class FolkloreMcp::Tools::Search::SearchTest < ActiveSupport::TestCase
  Search = FolkloreMcp::Tools::Search::Search

  def build(name, content: "", dir: "member/notes", tags: [], **attrs)
    asset = Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir:, name:, content:, **attrs)
    tags.each { |tag| AssetTag.create!(asset:, tag: Tag.find_or_create_by!(name: tag)) }
    asset
  end

  def rewrite(asset, content)
    Version.create!(asset:, content: asset.content, content_type: asset.content_type)
    asset.update!(content:)
  end

  test "resolves the asset search query from inside the tools namespace" do
    assert_same ::Assets::Search::ANY_TERM, FolkloreMcp::Tools::Search::Search::ANY_TERM
  end

  test "is registered as search, read-only and idempotent" do
    assert_equal "search", Search.name_value
    assert_includes FolkloreMcp::Tool.registered_tools, Search
    assert_equal({ openWorldHint: false, readOnlyHint: true }, Search.to_h[:annotations])
    assert_equal %w[query count results], Search.to_h[:outputSchema][:required]
  end

  test "returns matching assets as slug, name and dir lines with a snippet beneath each" do
    asset = build("needle.md", content: "intro line\nsome haystack body text that mentions the needle keyword here")

    response = Search.call(q: "needle", server_context: actor_context)

    refute response.to_h[:isError], text_of(response)
    lines = text_of(response).split("\n")
    assert_equal "#{asset.slug}  needle.md  (member/notes)", lines[0]
    assert_match(/\A {4}.*needle/, lines[1])
    refute_match(/\n/, lines[1].sub(/\A {4}/, ""))
  end

  test "structured content carries the same results" do
    asset = build("needle.md", content: "haystack body text")

    response = Search.call(q: "haystack", server_context: actor_context)

    structured = response.to_h[:structuredContent]
    assert_equal "haystack", structured[:query]
    assert_equal 1, structured[:count]
    result = structured[:results].first
    assert_equal asset.slug, result[:slug]
    assert_equal "needle.md", result[:name]
    assert_equal "member/notes", result[:dir]
    assert_equal "member/notes/needle.md", result[:location]
    assert_match(/haystack/, result[:snippet])
    assert_nil result[:displaced_at]
  end

  test "no results is said in words" do
    response = Search.call(q: "haystack", server_context: actor_context)

    refute response.to_h[:isError]
    assert_equal 'No results for "haystack"', text_of(response)
    assert_equal [], response.to_h[:structuredContent][:results]
  end

  test "filters by note status" do
    build("done-note.md", content: "haystack", status: "done")
    build("open-note.md", content: "haystack")

    response = Search.call(q: "haystack", status: "done", server_context: actor_context)

    assert_match(/done-note\.md/, text_of(response))
    refute_match(/open-note\.md/, text_of(response))
  end

  test "filters by task_status" do
    pending = build("pending-task.md", content: "haystack")
    done = build("done-task.md", content: "haystack")
    Task.create!(asset: pending, status: "pending")
    Task.create!(asset: done, status: "done")

    response = Search.call(q: "haystack", task_status: "pending", server_context: actor_context)

    assert_match(/pending-task\.md/, text_of(response))
    refute_match(/done-task\.md/, text_of(response))
  end

  test "scopes to within and excludes assets having exclude_tags" do
    build("keep.md", content: "haystack", tags: %w[review])
    build("drop.md", content: "haystack", tags: %w[review done])
    build("elsewhere.md", content: "haystack", dir: "member/other", tags: %w[review])

    response = Search.call(q: "haystack", within: "member/notes", tags: %w[review], exclude_tags: %w[done],
                           server_context: actor_context)

    assert_match(/keep\.md/, text_of(response))
    refute_match(/drop\.md/, text_of(response))
    refute_match(/elsewhere\.md/, text_of(response))
  end

  test "tags alone narrows to assets having every tag" do
    build("both.md", content: "haystack", tags: %w[review urgent])
    build("one.md", content: "haystack", tags: %w[review])

    response = Search.call(q: "haystack", tags: %w[review urgent], server_context: actor_context)

    assert_equal [ "both.md" ], response.to_h[:structuredContent][:results].map { |r| r[:name] }
  end

  test "stale: false returns only assets not past their review date" do
    build("overdue.md", content: "haystack", stale_after: Date.current - 1)
    build("fresh.md", content: "haystack")

    response = Search.call(q: "haystack", stale: false, server_context: actor_context)

    assert_equal [ "fresh.md" ], response.to_h[:structuredContent][:results].map { |r| r[:name] }
  end

  test "stale: true returns only assets past their review date" do
    build("overdue.md", content: "haystack", stale_after: Date.current - 1)
    build("fresh.md", content: "haystack")

    response = Search.call(q: "haystack", stale: true, server_context: actor_context)

    assert_match(/overdue\.md/, text_of(response))
    refute_match(/fresh\.md/, text_of(response))
  end

  test "stale: true without q lists every overdue asset, most overdue first" do
    build("recent.md", content: "one", stale_after: Date.current - 1)
    build("oldest.md", content: "two", stale_after: Date.current - 30)
    build("fresh.md", content: "three")

    response = Search.call(stale: true, server_context: actor_context)

    refute response.to_h[:isError], text_of(response)
    structured = response.to_h[:structuredContent]
    assert_nil structured[:query]
    assert_equal %w[oldest.md recent.md], structured[:results].map { |r| r[:name] }
  end

  test "stale: true without q says so when nothing is overdue" do
    response = Search.call(stale: true, server_context: actor_context)

    refute response.to_h[:isError]
    assert_equal "No overdue assets", text_of(response)
  end

  # Without a query or the review queue to list, a search would return the whole store.
  test "q is required unless stale is true" do
    [ {}, { stale: false } ].each do |args|
      response = Search.call(**args, server_context: actor_context)

      assert response.to_h[:isError]
      assert_equal "Invalid [invalid_argument]: q is required unless stale is true", text_of(response)
    end
  end

  test "include_versions finds an asset by content it used to have, snippeted from the version" do
    note = build("db.md", content: "we chose postgres for durability")
    rewrite(note, "we chose sqlite")

    response = Search.call(q: "postgres", include_versions: true, server_context: actor_context)

    lines = text_of(response).split("\n")
    assert_match(/db\.md/, lines[0])
    assert_match(/\(edited #{Date.current}\) .*postgres/, lines[1])
    assert_equal Date.current.iso8601, response.to_h[:structuredContent][:results].first[:displaced_at]
  end

  # The database matched this on stems; a literal substring check would miss the current
  # content and fall through to an old version, claiming the live result was edited away.
  test "a result whose current content matches by stemming is not labelled as edited" do
    note = build("db.md", content: "old: postgres databases rock")
    rewrite(note, "postgres database is our choice")

    response = Search.call(q: "postgres databases", include_versions: true, server_context: actor_context)

    line = text_of(response).split("\n")[1]
    refute_match(/edited/, line)
    assert_match(/postgres database is our choice/, line)
    assert_nil response.to_h[:structuredContent][:results].first[:displaced_at]
  end

  test "the snippet lands on the words of a multi-word query, not the head of the document" do
    filler = "intro filler " * 40
    build("deep.md", content: "#{filler}the production service restarted overnight")

    response = Search.call(q: "production service", server_context: actor_context)

    assert_match(/production service restarted/, text_of(response).split("\n")[1])
  end

  test "a bad limit is reported as Invalid rather than Internal error" do
    response = Search.call(q: "haystack", limit: -1, server_context: actor_context)

    assert response.to_h[:isError]
    assert_match(/\AInvalid \[[a-z_]+\]: limit/, text_of(response))
  end

  test "without include_versions displaced content stays hidden" do
    note = build("db.md", content: "we chose postgres")
    rewrite(note, "we chose sqlite")

    response = Search.call(q: "postgres", server_context: actor_context)

    assert_match(/No results/, text_of(response))
  end

  test "sort, limit and offset page through the results" do
    # Created out of name order, so the sort is what puts b second.
    %w[c.md a.md b.md].each { |name| build(name, content: "haystack") }

    response = Search.call(q: "haystack", sort: "name", limit: 1, offset: 1, server_context: actor_context)

    assert_equal [ "b.md" ], response.to_h[:structuredContent][:results].map { |r| r[:name] }
  end

  test "caps at 50 results when no limit is given" do
    51.times { |i| build("n#{i}.md", content: "haystack") }

    response = Search.call(q: "haystack", server_context: actor_context)

    assert_equal 50, response.to_h[:structuredContent][:count]
  end

  test "records the search in the log when logging is on" do
    ENV["FOLKLORE_SEARCH_LOG"] = "1"
    asset = build("needle.md", content: "haystack")

    Search.call(q: "haystack", within: "member/notes", tags: %w[], server_context: actor_context)

    log = SearchLog.sole
    assert_equal "haystack", log.query
    assert_equal({ "within" => "member/notes" }, log.filters)
    assert_equal [ asset.slug ], log.result_slugs
    assert_equal tokens(:member_default), log.token
  ensure
    ENV.delete("FOLKLORE_SEARCH_LOG")
  end

  test "requires an actor" do
    response = Search.call(q: "haystack")

    assert response.to_h[:isError]
    assert_match(/Unauthenticated/, text_of(response))
  end
end
