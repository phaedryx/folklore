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
    %w[read list create update upsert append delete restore versions verify set_stale_after set_status].each do |name|
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

  test "read by slug returns the asset once, as structured content with the same JSON as its text" do
    asset = create("plain.md", content: "just content")

    response = Tools::Read.call(ref: asset.slug, server_context: ctx)

    refute response.to_h[:isError]
    assert_equal Assets::Serializer.call(asset), structured(response)
    assert_equal JSON.parse(JSON.generate(structured(response))), JSON.parse(text_of(response))
    assert_equal 1, response.to_h[:content].size
  end

  test "read by location finds the same asset" do
    asset = create("loc.md", content: "by path")

    assert_equal asset.slug, structured(Tools::Read.call(ref: "member/notes/loc.md", server_context: ctx))[:slug]
  end

  test "read with include returns the slug and just those fields, in order" do
    asset = create("multi.md", content: "body text")
    ::Tags::Apply.mutate(actor: actor_for(:member_default), slug: asset.slug, tag: "tooling")

    assert_equal({ slug: asset.slug, tags: [ "tooling" ] }, structured(Tools::Read.call(ref: asset.slug, include: %w[tags], server_context: ctx)))

    both = Tools::Read.call(ref: asset.slug, include: %w[content name owner], server_context: ctx)
    assert_equal({ slug: asset.slug, name: "multi.md", owner: "member", content: "body text" }, structured(both))
    assert_equal %w[slug name owner content], JSON.parse(text_of(both)).keys
  end

  test "read with backlinks, created_by and version, querying backlinks once" do
    target = create("target.md")
    source = create("source.md", content: "see [[#{target.slug}]]")

    response = nil
    backlink_queries = count_queries(matching: /"links"/) do
      response = Tools::Read.call(ref: target.slug, include: %w[backlinks created_by version], server_context: ctx)
    end

    assert_equal 1, backlink_queries
    assert_equal({ slug: target.slug, backlinks: [ { slug: source.slug, location: "member/notes/source.md", name: "source.md" } ],
                   created_by: { handle: "member", agent: "default" }, version: 0 }, structured(response))
  end

  test "read refuses a field it does not know" do
    response = Tools::Read.call(ref: create("x.md").slug, include: %w[colour], server_context: ctx)

    assert response.to_h[:isError]
    assert_match(/\AInvalid/, text_of(response))
  end

  test "read returns Not found for an unknown or archived slug or location, and Invalid for a bad location" do
    gone = create("gone.md")
    ::Assets::Delete.mutate(actor: actor_for(:member_default), slug: gone.slug)

    [ "00000000", gone.slug, "member/notes/nope.md" ].each do |ref|
      response = Tools::Read.call(ref:, server_context: ctx)
      assert response.to_h[:isError]
      assert_equal "Not found: #{ref}", text_of(response)
    end
    assert_match(/\AInvalid: /, text_of(Tools::Read.call(ref: "member/", server_context: ctx)))
  end

  test "any member can read another's asset" do
    asset = create("shared.md", content: "x")

    refute Tools::Read.call(ref: asset.slug, server_context: ctx(:other_default)).to_h[:isError]
  end

  # read with an array

  test "read of an array returns each asset in order, with per-item errors carrying their code" do
    first = create("one.md", content: "1")
    create("two.md", content: "2")

    response = Tools::Read.call(ref: [ first.slug, "00000000", "member/notes/two.md", "member/" ], server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assets = structured(response)[:assets]
    assert_equal first.slug, assets[0][:slug]
    assert_equal({ ref: "00000000", error: "Not found: 00000000", code: "not_found" }, assets[1])
    assert_equal "2", assets[2][:content]
    assert_equal "invalid_location", assets[3][:code]
    assert_equal 2, structured(response)[:bytes_returned]
    refute structured(response)[:truncated]
  end

  test "read of an array omits content past max_bytes" do
    create("a.md", content: "aaaa")
    create("b.md", content: "bbbb")

    response = Tools::Read.call(ref: [ "member/notes/a.md", "member/notes/b.md" ], max_bytes: 4, server_context: ctx)

    assert structured(response)[:truncated]
    assert structured(response)[:assets][1][:content_omitted]
    refute structured(response)[:assets][1].key?(:content)
  end

  test "read of an array caps max_bytes and refuses an empty array or too many refs" do
    big = create("big.md", content: "x" * 600_000)
    also = create("also.md", content: "y" * 600_000)

    capped = Tools::Read.call(ref: [ big.slug, also.slug ], max_bytes: 10_000_000, server_context: ctx)
    assert structured(capped)[:truncated], "max_bytes is capped at #{::Assets::BulkRead::MAX_BYTES}"

    assert_match(/\AInvalid: /, text_of(Tools::Read.call(ref: [], server_context: ctx)))
    too_many = Tools::Read.call(ref: Array.new(::Assets::BulkRead::MAX_REFS + 1) { big.slug }, server_context: ctx)
    assert_equal "Invalid: read takes at most #{::Assets::BulkRead::MAX_REFS} refs, got #{::Assets::BulkRead::MAX_REFS + 1}", text_of(too_many)
  end

  # The ping skill picks its next task this way: read the queue without
  # content, then the first entry whose status is in_progress or pending.
  test "read reports a task's lifecycle state as its status" do
    pending = ::Tasks::Add.mutate(actor: actor_for(:member_default), path: "member/queue", name: "one.md", content: "x")
    held = ::Tasks::Add.mutate(actor: actor_for(:member_default), path: "member/queue", name: "two.md", content: "y")
    ::Tasks::Claim.mutate(actor: actor_for(:member_default, agent: "ping"), slug: held.slug)

    response = Tools::Read.call(ref: [ pending.slug, held.slug ], include: %w[kind status], server_context: ctx)

    assert_equal [ { slug: pending.slug, kind: "task", status: "pending" }, { slug: held.slug, kind: "task", status: "in_progress" } ],
                 structured(response)[:assets]
    assert_equal 0, structured(response)[:bytes_returned]
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

    slashed = Tools::List.call(path: "member/notes/", server_context: ctx)
    assert_equal text_of(response), text_of(slashed)

    assert_equal "No assets under member/empty", text_of(Tools::List.call(path: "member/empty", server_context: ctx))
  end

  test "list returns #{::Assets::List::DEFAULT_LIMIT} by default and the offset of the next page when there is one" do
    3.times { |i| create("p#{i}.md") }

    first = Tools::List.call(path: "member/notes", limit: 2, server_context: ctx)
    assert_equal 2, structured(first)[:assets].size
    assert_equal 2, structured(first)[:next_offset]
    assert_match(/\(more: offset 2\)\z/, text_of(first))

    last = Tools::List.call(path: "member/notes", limit: 2, offset: 2, server_context: ctx)
    assert_equal 1, structured(last)[:assets].size
    refute structured(last).key?(:next_offset)

    stub_const(::Assets::List, :DEFAULT_LIMIT, 2) do
      assert_equal 2, structured(Tools::List.call(path: "member/notes", server_context: ctx))[:assets].size
    end
  end

  # create / update / upsert / append

  test "create then read round-trip, stamping the agent" do
    response = Tools::Create.call(path: "member/notes", name: "x.md", content: "hi there", tags: %w[A], server_context: ctx(agent: "ping"))

    refute response.to_h[:isError], text_of(response)
    slug = text_of(response)[/\ACreated (\w+) at member\/notes\/x\.md\z/, 1]
    assert slug
    assert_equal({ slug:, location: "member/notes/x.md", version: 0 }, structured(response))
    assert_equal "hi there", structured(Tools::Read.call(ref: slug, server_context: ctx))[:content]
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

  test "an oversized name or path is Invalid, not Internal error" do
    # Incompressible and long enough to overflow the btree entry on (dir,
    # name), which without a cap surfaced as Internal error.
    long_name = SecureRandom.alphanumeric(4000)
    response = Tools::Create.call(path: "member/notes", name: long_name, server_context: ctx)
    assert_equal "Invalid: name is 4000 characters, over the 255 character limit", text_of(response)

    response = Tools::Create.call(path: "member/#{SecureRandom.alphanumeric(4000)}", name: "a.md", server_context: ctx)
    assert_equal "Invalid: path is 4007 characters, over the 1024 character limit", text_of(response)

    asset = create("u.md")
    response = Tools::Update.call(slug: asset.slug, name: long_name, server_context: ctx)
    assert_equal "Invalid: name is 4000 characters, over the 255 character limit", text_of(response)
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

  # move

  test "move changes the location and keeps the slug" do
    asset = create("m.md")

    response = Tools::Move.call(slug: asset.slug, path: "member/done", server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assert_equal "Moved #{asset.slug} to member/done/m.md", text_of(response)
    assert_equal({ slug: asset.slug, location: "member/done/m.md", version: 1 }, structured(response))
    assert_match(/\AConflict/, text_of(Tools::Move.call(slug: create("m.md").slug, path: "member/done", server_context: ctx)))
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
    assert_match(/\A- #{asset.versions.sole.id}  \d{4}-\d{2}-\d{2}T\S+  by member\/ping  \(text\/markdown\)\z/, text_of(response))
    version = structured(response)[:versions].first
    assert_equal asset.versions.first.id, version[:id]
    assert_equal({ handle: "member", agent: "ping" }, version[:actor])

    assert_equal "No prior versions", text_of(Tools::Versions.call(slug: create("n.md").slug, server_context: ctx))
    assert_equal "Not found: 00000000", text_of(Tools::Versions.call(slug: "00000000", server_context: ctx))
  end

  test "versions with an id returns that version's content, once" do
    asset = create("v.md", content: "v1")
    ::Assets::Update.mutate(actor: actor_for(:member_default, agent: "ping"), slug: asset.slug, content: "v2")
    old = asset.versions.sole

    response = Tools::Versions.call(slug: asset.slug, id: old.id, server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    version = structured(response)[:versions].sole
    assert_equal({ id: old.id, content: "v1", content_type: "text/markdown", actor: { handle: "member", agent: "ping" } },
                 version.slice(:id, :content, :content_type, :actor))
    assert_equal JSON.parse(JSON.generate(structured(response))), JSON.parse(text_of(response))

    other = create("other.md", content: "a")
    ::Assets::Update.mutate(actor: actor_for(:member_default), slug: other.slug, content: "b")
    assert_equal "Not found: version #{other.versions.sole.id} is not on #{asset.slug}",
                 text_of(Tools::Versions.call(slug: asset.slug, id: other.versions.sole.id, server_context: ctx))
  end

  test "restore with a version puts that content back, keeping the overwritten text as a version" do
    asset = create("r.md", content: "mine")
    ::Assets::Update.mutate(actor: actor_for(:member_default), slug: asset.slug, content: "clobbered")
    mine = asset.versions.sole

    response = Tools::Restore.call(slug: asset.slug, version: mine.id, server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assert_equal "Restored #{asset.slug} to version #{mine.id}", text_of(response)
    assert_equal "mine", asset.reload.content
    assert_equal %w[mine clobbered], asset.versions.order(:id).pluck(:content)
    assert_equal({ slug: asset.slug, location: asset.location, version: asset.lock_version }, structured(response))
    assert_match(/\ANot found: version 0 /, text_of(Tools::Restore.call(slug: asset.slug, version: 0, server_context: ctx)))
    assert_match(/\AForbidden/, text_of(Tools::Restore.call(slug: asset.slug, version: mine.id, server_context: ctx(:other_default))))
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

  test "an argument a tool does not take is refused as invalid, not an internal error" do
    asset = create("extra.md", content: "x")

    { "read" => :ref, "verify" => :slug }.each do |name, key|
      tool = FolkloreMcp.tool_classes.find { |klass| klass.name_value == name }
      response = tool.call(key => asset.slug, bogus: "ping", server_context: ctx)

      assert response.to_h[:isError], "#{name} accepted an unknown argument"
      assert_equal "Invalid: unknown argument bogus", text_of(response)
    end
    assert_nil asset.reload.verified_at
  end
end
