require "test_helper"

class FolkloreMcp::Tools::TasksTest < ActiveSupport::TestCase
  Tools = FolkloreMcp::Tools::Tasks

  def ctx(fixture = :member_default, agent: nil)
    actor_context(fixture, agent:)
  end

  def member(agent: nil)
    actor_for(:member_default, agent:)
  end

  def add(name, path: "member/inbox", tags: [])
    ::Tasks::Add.mutate(actor: member, path:, name:, content: "", tags:)
  end

  def structured(response)
    response.to_h[:structuredContent]
  end

  def slug_from(response)
    text_of(response)[/Added task (\w+)/, 1]
  end

  test "the task wire names are registered with annotations and output schemas" do
    tools = FolkloreMcp.tool_classes.index_by(&:name_value)
    %w[add_task claim_task complete_task fail_task get_pending_tasks].each do |name|
      assert tools[name], "#{name} is not registered"
      assert tools[name].to_h[:outputSchema], "#{name} has no output schema"
    end
    assert tools["get_pending_tasks"].to_h[:annotations][:readOnlyHint]
    assert tools["complete_task"].to_h[:annotations][:idempotentHint]
    refute tools["claim_task"].to_h[:annotations][:readOnlyHint]
  end

  test "the claim, complete and fail tools take an optional agent, and claim_task an optional slug" do
    schemas = FolkloreMcp.tool_classes.index_by(&:name_value).transform_values { |t| t.to_h[:inputSchema] }

    %w[claim_task complete_task fail_task].each do |name|
      assert_includes schemas[name][:properties].keys.map(&:to_s), "agent", name
    end
    claim = schemas["claim_task"]
    assert_equal %w[agent lease_seconds path_prefix slug tags], claim[:properties].keys.map(&:to_s).sort
    assert_empty Array(claim[:required])
    assert_equal %w[reason slug], schemas["fail_task"][:required].map(&:to_s).sort
    assert_equal %w[path_prefix], schemas["get_pending_tasks"][:required].map(&:to_s)
    assert_includes schemas["get_pending_tasks"][:properties].keys.map(&:to_s), "status"
    assert_includes schemas["complete_task"][:properties].keys.map(&:to_s), "note"
  end

  # add_task

  test "add_task creates a pending task and passes tags through" do
    response = Tools::Add.call(path: "member/stories/sc-1", name: "step.md", content: "do the thing", tags: [ "urgent" ], server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    asset = Asset.find_by!(slug: slug_from(response))
    assert_equal "Added task #{asset.slug} at member/stories/sc-1/step.md", text_of(response)
    assert_equal "pending", asset.task.status
    assert_equal [ "urgent" ], asset.tags.pluck(:name)
    assert_equal({ slug: asset.slug, location: "member/stories/sc-1/step.md", status: "pending" }, structured(response))
  end

  test "add_task reports Forbidden for another member's workspace and Conflict for a taken name" do
    forbidden = Tools::Add.call(path: "other/stories", name: "x.md", server_context: ctx)
    assert forbidden.to_h[:isError]
    assert_match(/\AForbidden: /, text_of(forbidden))

    add("dup.md")
    taken = Tools::Add.call(path: "member/inbox", name: "dup.md", server_context: ctx)
    assert_match(/\AConflict: /, text_of(taken))
  end

  # claim_task

  test "claim_task claims by slug for the token's agent" do
    asset = add("task.md")

    response = Tools::Claim.call(slug: asset.slug, server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    task = asset.task.reload
    assert_equal "Claimed #{asset.slug} at member/inbox/task.md as member/default until #{task.lease_until.iso8601}", text_of(response)
    assert_equal({ slug: asset.slug, location: "member/inbox/task.md", claimed_by: "member/default",
                   lease_until: task.lease_until.iso8601, attempts: 1 }, structured(response))
  end

  test "claim_task with agent records that agent, and another agent on the token gets Already claimed" do
    asset = add("task.md")

    Tools::Claim.call(slug: asset.slug, agent: "ping", server_context: ctx)
    response = Tools::Claim.call(slug: asset.slug, agent: "pong", server_context: ctx)

    assert response.to_h[:isError]
    assert_match(/\AAlready claimed: #{asset.slug} is claimed by member\/ping until /, text_of(response))
    assert_equal "ping", asset.task.reload.claimed_by_agent
  end

  test "claim_task honours lease_seconds and refuses a bad one" do
    asset = add("task.md")

    Tools::Claim.call(slug: asset.slug, lease_seconds: 120, server_context: ctx)
    assert_in_delta 120.seconds.from_now, asset.task.reload.lease_until, 5.seconds

    bad = Tools::Claim.call(slug: add("t2.md").slug, lease_seconds: 0, server_context: ctx)
    assert_match(/\AInvalid: lease_seconds/, text_of(bad))
  end

  test "claim_task without a slug claims the oldest pending task under path_prefix with the given tags" do
    travel_to(1.hour.ago) { add("old.md", path: "member/backlog") }
    tagged = add("tagged.md", path: "member/backlog", tags: %w[urgent])

    by_tag = Tools::Claim.call(path_prefix: "member/backlog", tags: %w[urgent], agent: "ping", server_context: ctx)
    oldest = Tools::Claim.call(path_prefix: "member/backlog", agent: "pong", server_context: ctx)
    none = Tools::Claim.call(path_prefix: "member/backlog", server_context: ctx)

    assert_equal tagged.slug, structured(by_tag)[:slug]
    assert_equal "member/backlog/old.md", structured(oldest)[:location]
    assert none.to_h[:isError]
    assert_equal "No pending task: nothing to claim under member/backlog", text_of(none)
  end

  test "claim_task with neither slug nor path_prefix is Invalid" do
    response = Tools::Claim.call(server_context: ctx)

    assert_match(/\AInvalid: pass a slug/, text_of(response))
  end

  test "claim_task reports Not a task, Not found and a bad agent" do
    note = ::Assets::Create.mutate(actor: member, path: "member/notes", name: "n.md", content: "")

    assert_equal "Not a task: #{note.slug}", text_of(Tools::Claim.call(slug: note.slug, server_context: ctx))
    assert_equal "Not found: 00000000", text_of(Tools::Claim.call(slug: "00000000", server_context: ctx))
    assert_match(/\AInvalid: agent/, text_of(Tools::Claim.call(slug: note.slug, agent: "Bad Agent", server_context: ctx)))
  end

  test "an agent override from a web session is refused" do
    asset = add("task.md")

    response = Tools::Claim.call(slug: asset.slug, agent: "ping", server_context: { actor: Actor.for_user(users(:member)) })

    assert response.to_h[:isError]
    assert_match(/\AInvalid: agent override needs a token/, text_of(response))
    assert_equal "pending", asset.task.reload.status
  end

  # complete_task / fail_task

  test "complete_task by the claiming agent finishes the task with a note" do
    asset = add("task.md")
    ::Tasks::Claim.mutate(actor: member(agent: "ping"), slug: asset.slug)

    response = Tools::Complete.call(slug: asset.slug, note: "merged", agent: "ping", server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assert_equal "Completed #{asset.slug}", text_of(response)
    assert_equal({ slug: asset.slug, status: "done", note: "merged" }, structured(response))
    assert_equal "merged", Event.where(asset_id: asset.id, action: "task_completed").sole.metadata["note"]
  end

  test "complete_task by another agent on the same token is Wrong claimer" do
    asset = add("task.md")
    ::Tasks::Claim.mutate(actor: member(agent: "ping"), slug: asset.slug)

    response = Tools::Complete.call(slug: asset.slug, agent: "pong", server_context: ctx)

    assert response.to_h[:isError]
    assert_equal "Wrong claimer: #{asset.slug} is claimed by member/ping, not member/pong", text_of(response)
  end

  test "fail_task by the claiming agent records the reason; without the claim it is Wrong claimer" do
    asset = add("task.md")
    ::Tasks::Claim.mutate(actor: member(agent: "ping"), slug: asset.slug)

    wrong = Tools::Fail.call(slug: asset.slug, reason: "x", server_context: ctx(:other_default))
    assert_match(/\AWrong claimer: /, text_of(wrong))

    response = Tools::Fail.call(slug: asset.slug, reason: "API timeout", agent: "ping", server_context: ctx)
    refute response.to_h[:isError], text_of(response)
    assert_equal "Failed #{asset.slug}: API timeout", text_of(response)
    assert_equal({ slug: asset.slug, status: "failed", reason: "API timeout" }, structured(response))
  end

  test "fail_task with a blank reason is Invalid" do
    asset = add("task.md")
    ::Tasks::Claim.mutate(actor: member, slug: asset.slug)

    assert_match(/\AInvalid: a reason is required/, text_of(Tools::Fail.call(slug: asset.slug, reason: "  ", server_context: ctx)))
  end

  test "a note or reason over the length limit is Invalid" do
    asset = add("task.md")
    ::Tasks::Claim.mutate(actor: member, slug: asset.slug)
    long = "n" * (Task::MAX_NOTE_LENGTH + 1)

    assert_equal "Invalid: note is 10001 characters, over the 10000 character limit",
                 text_of(Tools::Complete.call(slug: asset.slug, note: long, server_context: ctx))
    assert_equal "Invalid: reason is 10001 characters, over the 10000 character limit",
                 text_of(Tools::Fail.call(slug: asset.slug, reason: long, server_context: ctx))
  end

  test "full task lifecycle through the tools records added, claimed, completed" do
    slug = slug_from(Tools::Add.call(path: "member/inbox", name: "life.md", server_context: ctx))

    Tools::Claim.call(slug:, agent: "ping", server_context: ctx)
    Tools::Complete.call(slug:, agent: "ping", server_context: ctx)

    asset = Asset.find_by!(slug:)
    assert_equal "done", asset.task.status
    assert_equal %w[task_added task_claimed task_completed], Event.where(asset_id: asset.id).order(:id).pluck(:action)
  end

  # get_pending_tasks

  test "get_pending_tasks lists pending tasks under a prefix as slug  location lines, oldest first" do
    a = travel_to(1.hour.ago) { add("a.md", path: "member/stories/proj-123/tasks") }
    b = add("b.md", path: "member/stories/proj-123/tasks")
    add("c.md", path: "member/stories/proj-999")

    response = Tools::Pending.call(path_prefix: "member/stories/proj-123", server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assert_equal "#{a.slug}  member/stories/proj-123/tasks/a.md\n#{b.slug}  member/stories/proj-123/tasks/b.md", text_of(response)
    row = structured(response)[:tasks].first
    assert_equal({ slug: a.slug, location: "member/stories/proj-123/tasks/a.md", name: "a.md", dir: "member/stories/proj-123/tasks",
                   status: "pending", claimed_by: nil, lease_until: nil, attempts: 0, tags: [], created_at: a.created_at.iso8601 }, row)
  end

  test "get_pending_tasks with status in_progress finds a claim held when an agent died" do
    held = add("held.md")
    add("waiting.md")
    ::Tasks::Claim.mutate(actor: member(agent: "ping"), slug: held.slug)

    pending = Tools::Pending.call(path_prefix: "member/inbox", server_context: ctx)
    in_progress = Tools::Pending.call(path_prefix: "member/inbox", status: "in_progress", server_context: ctx)
    all = Tools::Pending.call(path_prefix: "member/inbox", status: "all", server_context: ctx)

    refute_match(/held\.md/, text_of(pending))
    assert_equal "#{held.slug}  member/inbox/held.md", text_of(in_progress)
    assert_equal "member/ping", structured(in_progress)[:tasks].first[:claimed_by]
    assert_equal 2, structured(all)[:tasks].size
  end

  test "get_pending_tasks filters by tags, and says so plainly when empty" do
    add("urgent.md", tags: %w[urgent])
    add("plain.md")

    tagged = Tools::Pending.call(path_prefix: "member/inbox", tags: %w[urgent], server_context: ctx)
    assert_match(/urgent\.md/, text_of(tagged))
    refute_match(/plain\.md/, text_of(tagged))

    empty = Tools::Pending.call(path_prefix: "member/nothing-here", server_context: ctx)
    refute empty.to_h[:isError]
    assert_equal "No pending tasks under member/nothing-here", text_of(empty)
    assert_equal "No done tasks under member/inbox", text_of(Tools::Pending.call(path_prefix: "member/inbox", status: "done", server_context: ctx))
    assert_equal({ tasks: [], truncated: false }, structured(empty))
  end

  test "get_pending_tasks returns at most 100 tasks unless told otherwise, and pages with offset" do
    101.times { |i| add(format("t%03d.md", i)) }

    response = Tools::Pending.call(path_prefix: "member/inbox", server_context: ctx)
    first = structured(response)[:tasks]
    assert_equal 100, first.size
    assert_equal "t000.md", first.first[:name]
    assert structured(response)[:truncated]
    assert_match(/\n\(100 shown; pass offset: 100 for more\)\z/, text_of(response))

    response = Tools::Pending.call(path_prefix: "member/inbox", offset: 100, server_context: ctx)
    assert_equal %w[t100.md], structured(response)[:tasks].map { |row| row[:name] }
    refute structured(response)[:truncated]
    refute_match(/for more/, text_of(response))

    two = structured(Tools::Pending.call(path_prefix: "member/inbox", limit: 2, offset: 1, server_context: ctx))[:tasks]
    assert_equal %w[t001.md t002.md], two.map { |row| row[:name] }
  end

  test "get_pending_tasks refuses a limit above the maximum or below one" do
    [ 0, ::Tasks::List::MAX_LIMIT + 1 ].each do |limit|
      response = Tools::Pending.call(path_prefix: "member/inbox", limit:, server_context: ctx)

      assert_match(/\AInvalid: limit must be between 1 and 500/, text_of(response), limit)
    end
  end

  test "get_pending_tasks refuses an unknown status" do
    response = Tools::Pending.call(path_prefix: "member/inbox", status: "open", server_context: ctx)

    assert_match(/\AInvalid: status must be one of/, text_of(response))
  end

  test "set_status still refuses a task" do
    asset = add("t.md")

    response = FolkloreMcp::Tools::Assets::SetStatus.call(slug: asset.slug, status: "done", server_context: ctx)

    assert response.to_h[:isError]
  end
end
