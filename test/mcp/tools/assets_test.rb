require "test_helper"

class FolkloreMcp::Tools::AssetsTest < ActiveSupport::TestCase
  Tools = FolkloreMcp::Tools::Assets

  def ctx(fixture = :member_default, agent: nil)
    actor_context(fixture, agent:)
  end

  def create(name, content: "", path: "member/notes", **attrs)
    ::Assets::Create.mutate(actor: actor_for(:member_default), path:, name:, content:, **attrs)
  end

  def structured(response)
    response.to_h[:structuredContent]
  end

  test "the asset wire names are registered with annotations and output schemas" do
    tools = FolkloreMcp.tool_classes.index_by(&:name_value)
    %w[read read_path bulk_read list create update upsert append delete restore versions verify set_stale_after set_status].each do |name|
      tool = tools[name]
      assert tool, "#{name} is not registered"
      assert tool.to_h[:outputSchema], "#{name} has no output schema"
      assert_kind_of Hash, tool.to_h[:annotations]
    end
    assert tools["read"].to_h[:annotations][:readOnlyHint]
    assert tools["delete"].to_h[:annotations][:destructiveHint]
    assert tools["upsert"].to_h[:annotations][:idempotentHint]
    refute tools["create"].to_h[:annotations][:readOnlyHint]
  end

  # read

  test "read with no flags returns exactly the content, with the slug and content beside it" do
    asset = create("plain.md", content: "just content")

    response = Tools::Read.call(slug: asset.slug, server_context: ctx)

    refute response.to_h[:isError]
    assert_equal "just content", text_of(response)
    assert_equal asset.slug, structured(response)[:slug]
  end

  test "read serializes the asset and queries its backlinks once for both text and structured content" do
    target = create("target.md", content: "t")
    create("source.md", content: "see [[#{target.slug}]]")

    backlink_queries = count_queries(matching: /"links"/) do
      response = Tools::Read.call(slug: target.slug, backlinks: true, tags: true, server_context: ctx)
      assert_match(/source\.md/, text_of(response))
      assert_equal 1, structured(response)[:backlinks].size
    end
    tag_queries = count_queries(matching: /"tags"/) { Tools::Read.call(slug: target.slug, tags: true, server_context: ctx) }

    assert_equal 1, backlink_queries
    assert_equal 1, tag_queries
  end

  test "read with format json returns the structured asset" do
    asset = create("json.md", content: "body")

    response = Tools::Read.call(slug: asset.slug, format: "json", server_context: ctx)

    refute response.to_h[:isError], response.to_h.inspect
    assert_equal "body", JSON.parse(text_of(response))["content"]
    assert_equal AssetSerializer.call(asset), structured(response)
  end

  test "read with metadata flags returns those fields in order, then the body after a separator" do
    asset = create("multi.md", content: "body text")
    ::Tags::Apply.mutate(actor: actor_for(:member_default), slug: asset.slug, tag: "tooling")

    only_tags = Tools::Read.call(slug: asset.slug, tags: true, server_context: ctx)
    assert_equal "tags: tooling", text_of(only_tags)

    several = Tools::Read.call(slug: asset.slug, name: true, content_type: true, created_at: true, server_context: ctx)
    assert_match(/\Aname: multi\.md\ncontent_type: text\/markdown\ncreated_at: \d{4}-/, text_of(several))
    refute_match(/body/, text_of(several))

    both = Tools::Read.call(slug: asset.slug, name: true, content: true, server_context: ctx)
    assert_equal "name: multi.md\n---\nbody text", text_of(both)
    assert_equal({ slug: asset.slug, name: "multi.md", content: "body text" }, structured(both))
  end

  test "read with backlinks, created_by and version" do
    target = create("target.md")
    source = create("source.md", content: "see [[#{target.slug}]]")

    response = Tools::Read.call(slug: target.slug, backlinks: true, created_by: true, version: true, server_context: ctx)

    assert_equal "backlinks:\n#{source.slug}  member/notes/source.md\ncreated_by: member/default\nversion: 0", text_of(response)
    assert_equal [ { slug: source.slug, location: "member/notes/source.md", name: "source.md" } ], structured(response)[:backlinks]
  end

  test "read returns Not found for an unknown or deleted slug" do
    gone = create("gone.md")
    ::Assets::Delete.mutate(actor: actor_for(:member_default), slug: gone.slug)

    [ "00000000", gone.slug ].each do |slug|
      response = Tools::Read.call(slug:, server_context: ctx)
      assert response.to_h[:isError]
      assert_equal "Not found: #{slug}", text_of(response)
    end
  end

  test "any member can read another's asset" do
    asset = create("shared.md", content: "x")

    refute Tools::Read.call(slug: asset.slug, server_context: ctx(:other_default)).to_h[:isError]
  end

  # read_path

  test "read_path resolves a location or path + name, as text or json, with selected fields" do
    asset = create("loc.md", content: "by path")

    assert_equal "by path", text_of(Tools::ReadPath.call(location: "member/notes/loc.md", server_context: ctx))
    assert_equal "by path", text_of(Tools::ReadPath.call(path: "member/notes", name: "loc.md", server_context: ctx))

    json = Tools::ReadPath.call(location: "member/notes/loc.md", format: "json", server_context: ctx)
    assert_equal asset.slug, structured(json)[:slug]

    partial = Tools::ReadPath.call(location: "member/notes/loc.md", with: %w[name content], server_context: ctx)
    assert_equal "name: loc.md\n---\nby path", text_of(partial)
  end

  test "read_path reports Not found with the address and Invalid for a bad address" do
    missing = Tools::ReadPath.call(location: "member/notes/nope.md", server_context: ctx)
    assert_equal "Not found: member/notes/nope.md", text_of(missing)

    bad = Tools::ReadPath.call(path: "member/notes", server_context: ctx)
    assert bad.to_h[:isError]
    assert_match(/\AInvalid: /, text_of(bad))
  end

  # bulk_read

  test "bulk_read returns assets by slug and location as text and as json, with per-item errors" do
    first = create("one.md", content: "1")
    create("two.md", content: "2")

    json = Tools::BulkRead.call(slugs: [ first.slug, "00000000" ], locations: [ "member/notes/two.md" ], format: "json", server_context: ctx)
    refute json.to_h[:isError], json.to_h.inspect
    assets = structured(json)[:assets]
    assert_equal first.slug, assets[0][:slug]
    assert_equal "not_found", assets[1][:error]
    assert_equal "2", assets[2][:content]
    assert_equal 2, structured(json)[:bytes_returned]
    refute structured(json)[:truncated]

    text = Tools::BulkRead.call(slugs: [ first.slug, "00000000" ], server_context: ctx)
    assert_equal "#{first.slug}  member/notes/one.md\n---\n1\n\n00000000: error not_found", text_of(text)
  end

  test "bulk_read omits content past max_bytes and refuses an empty request" do
    create("a.md", content: "aaaa")
    create("b.md", content: "bbbb")

    response = Tools::BulkRead.call(locations: [ "member/notes/a.md", "member/notes/b.md" ], max_bytes: 4, format: "json", server_context: ctx)
    assert structured(response)[:truncated]
    assert structured(response)[:assets][1][:content_omitted]
    refute structured(response)[:assets][1].key?(:content)

    empty = Tools::BulkRead.call(server_context: ctx)
    assert empty.to_h[:isError]
  end

  # list

  test "list keeps the slug-location line format, filters by tags, and omits archived assets" do
    a = create("a.md", tags: %w[shell])
    b = create("b.md")
    gone = create("gone.md")
    ::Assets::Delete.mutate(actor: actor_for(:member_default), slug: gone.slug)

    response = Tools::List.call(path: "member/notes", server_context: ctx)
    assert_equal "#{a.slug}  member/notes/a.md\n#{b.slug}  member/notes/b.md", text_of(response)
    assert_equal [ a.slug, b.slug ], structured(response)[:assets].map { |row| row[:slug] }
    assert_equal "member/notes/a.md", structured(response)[:assets].first[:location]

    tagged = Tools::List.call(path: "member/notes", tags: %w[shell], server_context: ctx)
    assert_equal "#{a.slug}  member/notes/a.md", text_of(tagged)

    assert_equal "No assets under member/empty", text_of(Tools::List.call(path: "member/empty", server_context: ctx))
  end

  # create / update / upsert / append

  test "create then read round-trip, stamping the agent" do
    response = Tools::Create.call(path: "member/notes", name: "x.md", content: "hi there", tags: %w[A], server_context: ctx(agent: "ping"))

    refute response.to_h[:isError], text_of(response)
    slug = text_of(response)[/\ACreated (\w+) at member\/notes\/x\.md\z/, 1]
    assert slug
    assert_equal({ slug:, location: "member/notes/x.md", version: 0 }, structured(response))
    assert_equal "hi there", text_of(Tools::Read.call(slug:, server_context: ctx))
    assert_equal "ping", Asset.find_by!(slug:).created_by_agent
  end

  test "create reports reserved, forbidden, invalid and taken paths" do
    create("dup.md")

    {
      { path: "member/archive", name: "x.md" } => /\AInvalid: member\/archive is reserved/,
      { path: "other/notes", name: "x.md" } => /\AForbidden: cannot write to other\/notes/,
      { path: "member/../x", name: "x.md" } => /\AInvalid: path segments/,
      { path: "member/notes", name: "a b.md" } => /\AInvalid: name cannot contain whitespace/,
      { path: "member/notes", name: "dup.md" } => /\AConflict: member\/notes\/dup\.md already exists/
    }.each do |args, pattern|
      response = Tools::Create.call(**args, server_context: ctx)
      assert response.to_h[:isError], args.inspect
      assert_match pattern, text_of(response)
    end
  end

  test "update changes content, snapshots a version, and reports the new version" do
    asset = create("u.md", content: "v1")

    response = Tools::Update.call(slug: asset.slug, content: "v2", server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assert_equal "Updated #{asset.slug}", text_of(response)
    assert_equal({ slug: asset.slug, location: "member/notes/u.md", version: 1 }, structured(response))
    assert_equal "v2", asset.reload.content
    assert_equal 1, asset.versions.count
  end

  test "content over the cap is reported as Invalid, not Internal error" do
    asset = create("big.md")

    response = Tools::Append.call(slug: asset.slug, text: "x" * (Asset::MAX_CONTENT_BYTES + 1), server_context: ctx)

    assert response.to_h[:isError]
    assert_match(/\AInvalid: content is \d+ bytes, over the 1 MiB cap/, text_of(response))
  end

  test "update with a stale expected_version is a Conflict naming the current version" do
    asset = create("u.md", content: "v1")
    Tools::Update.call(slug: asset.slug, content: "v2", server_context: ctx)

    response = Tools::Update.call(slug: asset.slug, content: "v3", expected_version: 0, server_context: ctx)

    assert response.to_h[:isError]
    assert_equal "Conflict: #{asset.slug} is at version 1", text_of(response)
    assert_equal "v2", asset.reload.content

    ok = Tools::Update.call(slug: asset.slug, content: "v3", expected_version: 1, server_context: ctx)
    refute ok.to_h[:isError], text_of(ok)
  end

  test "update returns Not found and Forbidden" do
    asset = create("u.md")

    assert_equal "Not found: 00000000", text_of(Tools::Update.call(slug: "00000000", content: "x", server_context: ctx))
    assert_match(/\AForbidden: /, text_of(Tools::Update.call(slug: asset.slug, content: "x", server_context: ctx(:other_default))))
  end

  test "upsert creates then updates" do
    created = Tools::Upsert.call(path: "member/notes", name: "up.md", content: "first", server_context: ctx)
    refute created.to_h[:isError], text_of(created)
    slug = text_of(created)[/\ACreated (\w+) at member\/notes\/up\.md\z/, 1]
    assert_equal({ slug:, location: "member/notes/up.md", version: 0, created: true }, structured(created))

    updated = Tools::Upsert.call(path: "member/notes", name: "up.md", content: "second", server_context: ctx)
    assert_equal "Updated #{slug}", text_of(updated)
    assert_equal({ slug:, location: "member/notes/up.md", version: 1, created: false }, structured(updated))
    assert_equal 1, Asset.find_by!(slug:).versions.count
  end

  test "append adds a line and snapshots" do
    asset = create("a.md", content: "line 1")

    response = Tools::Append.call(slug: asset.slug, text: "line 2", server_context: ctx)

    assert_equal "Appended to #{asset.slug}", text_of(response)
    assert_equal({ slug: asset.slug, version: 1 }, structured(response))
    assert_equal "line 1\nline 2", asset.reload.content
    assert_equal "Not found: 00000000", text_of(Tools::Append.call(slug: "00000000", text: "x", server_context: ctx))
  end

  # delete / restore

  test "delete then restore round-trip, with the conflicts in between" do
    asset = create("d.md")

    del = Tools::Delete.call(slug: asset.slug, server_context: ctx)
    assert_equal "Deleted #{asset.slug}", text_of(del)
    assert asset.reload.deleted_at?

    again = Tools::Delete.call(slug: asset.slug, server_context: ctx)
    assert_equal "Conflict: #{asset.slug} is already deleted", text_of(again)

    res = Tools::Restore.call(slug: asset.slug, server_context: ctx)
    assert_equal "Restored #{asset.slug}", text_of(res)
    refute asset.reload.deleted_at?

    not_deleted = Tools::Restore.call(slug: asset.slug, server_context: ctx)
    assert_equal "Conflict: #{asset.slug} is not deleted", text_of(not_deleted)
  end

  # versions

  test "versions lists history newest first with the actor, or says there is none" do
    asset = create("v.md", content: "v1")
    ::Assets::Update.mutate(actor: actor_for(:member_default, agent: "ping"), slug: asset.slug, content: "v2")

    response = Tools::Versions.call(slug: asset.slug, server_context: ctx)

    refute response.to_h[:isError]
    assert_match(/\A- \d{4}-\d{2}-\d{2}T\S+  by member\/ping  \(text\/markdown\)\z/, text_of(response))
    version = structured(response)[:versions].first
    assert_equal asset.versions.first.id, version[:id]
    assert_equal({ handle: "member", agent: "ping" }, version[:actor])

    assert_equal "No prior versions", text_of(Tools::Versions.call(slug: create("n.md").slug, server_context: ctx))
    assert_equal "Not found: 00000000", text_of(Tools::Versions.call(slug: "00000000", server_context: ctx))
  end

  # verify / set_stale_after / set_status

  test "verify records verification and the review date" do
    asset = create("n.md", content: "x")

    response = Tools::Verify.call(slug: asset.slug, stale_after: "2026-12-01", server_context: ctx(agent: "ping"))

    refute response.to_h[:isError], text_of(response)
    assert_match(/\AVerified #{asset.slug} at \S+ — re-check after 2026-12-01\z/, text_of(response))
    assert_equal "2026-12-01", structured(response)[:stale_after]
    assert_equal Date.new(2026, 12, 1), asset.reload.stale_after
    assert_equal "ping", asset.verified_by_agent

    plain = Tools::Verify.call(slug: asset.slug, server_context: ctx)
    assert_match(/re-check after 2026-12-01/, text_of(plain), "omitting stale_after leaves it")
  end

  test "verify reports not found, forbidden and an unparseable date" do
    asset = create("n.md")

    assert_equal "Not found: 00000000", text_of(Tools::Verify.call(slug: "00000000", server_context: ctx))
    assert_match(/\AForbidden/, text_of(Tools::Verify.call(slug: asset.slug, server_context: ctx(:other_default))))
    assert_match(/\AInvalid: stale_after/, text_of(Tools::Verify.call(slug: asset.slug, stale_after: "next tuesday", server_context: ctx)))
  end

  test "set_stale_after schedules and clears a review date without verifying" do
    asset = create("n.md")

    set = Tools::SetStaleAfter.call(slug: asset.slug, stale_after: "2026-12-01", server_context: ctx)
    assert_equal "#{asset.slug} due for re-check after 2026-12-01", text_of(set)
    assert_nil asset.reload.verified_at

    cleared = Tools::SetStaleAfter.call(slug: asset.slug, stale_after: "", server_context: ctx)
    assert_equal "Cleared the review date on #{asset.slug}", text_of(cleared)
    assert_nil structured(cleared)[:stale_after]

    assert_match(/\AInvalid: stale_after/, text_of(Tools::SetStaleAfter.call(slug: asset.slug, stale_after: "soon", server_context: ctx)))
    assert_match(/\AForbidden/, text_of(Tools::SetStaleAfter.call(slug: asset.slug, stale_after: "2026-12-01", server_context: ctx(:other_default))))
  end

  test "set_status sets, clears, and refuses tasks and bad values" do
    asset = create("s.md")

    done = Tools::SetStatus.call(slug: asset.slug, status: "done", server_context: ctx)
    assert_equal "Set status of #{asset.slug} to done", text_of(done)
    assert_equal({ slug: asset.slug, status: "done" }, structured(done))

    none = Tools::SetStatus.call(slug: asset.slug, status: "", server_context: ctx)
    assert_equal "Set status of #{asset.slug} to none", text_of(none)
    assert_nil asset.reload.status

    assert_match(/\AInvalid: status must be one of/, text_of(Tools::SetStatus.call(slug: asset.slug, status: "in_progress", server_context: ctx)))

    Task.create!(asset:, status: "pending")
    assert_match(/\AInvalid: #{asset.slug} is a task/, text_of(Tools::SetStatus.call(slug: asset.slug, status: "done", server_context: ctx)))
    assert_equal "Not found: 00000000", text_of(Tools::SetStatus.call(slug: "00000000", status: "done", server_context: ctx))
  end

  # The ping skill picks its next task this way: bulk_read in json without
  # content, then the first entry whose status is in_progress or pending.
  test "bulk_read json reports a task's lifecycle state as its status" do
    pending = ::Tasks::Add.mutate(actor: actor_for(:member_default), path: "member/queue", name: "one.md", content: "x")
    held = ::Tasks::Add.mutate(actor: actor_for(:member_default), path: "member/queue", name: "two.md", content: "y")
    ::Tasks::Claim.mutate(actor: actor_for(:member_default, agent: "ping"), slug: held.slug)

    response = Tools::BulkRead.call(slugs: [ pending.slug, held.slug ], include_content: false, format: "json", server_context: ctx)
    statuses = JSON.parse(text_of(response))["assets"].to_h { |asset| [ asset["slug"], asset["status"] ] }

    assert_equal({ pending.slug => "pending", held.slug => "in_progress" }, statuses)
    assert_equal "status: pending", text_of(Tools::Read.call(slug: pending.slug, status: true, server_context: ctx))
  end

  test "an argument a tool does not take is refused as invalid, not an internal error" do
    asset = create("extra.md", content: "x")

    %w[read verify].each do |name|
      tool = FolkloreMcp.tool_classes.find { |klass| klass.name_value == name }
      response = tool.call(slug: asset.slug, agent: "ping", server_context: ctx)

      assert response.to_h[:isError], "#{name} accepted an unknown argument"
      assert_equal "Invalid: unknown argument agent", text_of(response)
    end
    assert_nil asset.reload.verified_at
  end
end
