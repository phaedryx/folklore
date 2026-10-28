require "test_helper"

class Tasks::ListTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def add(name, path: "member/inbox", tags: [])
    Tasks::Add.mutate(actor: @actor, path:, name:, content: "", tags:)
  end

  # Moves a task's row to a status directly, so the listing is tested without
  # the claim mutation (Task 2 of this workstream).
  def set_status(asset, status, agent: "default")
    claimer = status == "in_progress" ? { claimed_by_user: @actor.user, claimed_by_token: @actor.token, claimed_by_agent: agent, lease_until: 30.minutes.from_now } : {}
    asset.task.update!(status:, **claimer)
  end

  def names(**args)
    Tasks::List.query(**{ path_prefix: "member/inbox", actor: @actor }.merge(args)).map(&:name)
  end

  test "lists pending tasks under the prefix by default" do
    add("a.md", path: "member/stories/sc-1")
    add("b.md", path: "member/stories/sc-1/tasks")
    add("c.md", path: "member/stories/sc-2")

    assert_equal %w[a.md b.md], names(path_prefix: "member/stories/sc-1").sort
  end

  test "pending excludes claimed, done, failed and cancelled tasks" do
    add("p.md")
    set_status(add("c.md"), "in_progress")
    set_status(add("d.md"), "done")
    set_status(add("f.md"), "failed")
    set_status(add("x.md"), "cancelled")

    assert_equal [ "p.md" ], names
  end

  test "status in_progress lists only claimed tasks" do
    add("p.md")
    set_status(add("c.md"), "in_progress")

    assert_equal [ "c.md" ], names(status: "in_progress")
  end

  test "status all lists every task regardless of status" do
    add("p.md")
    set_status(add("c.md"), "in_progress")
    set_status(add("d.md"), "done")

    assert_equal %w[c.md d.md p.md], names(status: "all").sort
  end

  test "done, failed and cancelled each list their own" do
    set_status(add("d.md"), "done")
    set_status(add("f.md"), "failed")
    set_status(add("x.md"), "cancelled")

    assert_equal [ "d.md" ], names(status: "done")
    assert_equal [ "f.md" ], names(status: "failed")
    assert_equal [ "x.md" ], names(status: "cancelled")
  end

  test "rejects an unknown status rather than listing nothing" do
    assert_raises(Tasks::InvalidStatusError) { names(status: "open") }
  end

  test "excludes notes, including a note hand-tagged 'task'" do
    add("task.md", path: "member/mix")
    Assets::Create.mutate(actor: @actor, path: "member/mix", name: "note.md", content: "", tags: [ "task" ])

    assert_equal [ "task.md" ], names(path_prefix: "member/mix", status: "all")
  end

  test "excludes deleted tasks" do
    asset = add("trashme.md")
    Assets::Delete.mutate(actor: @actor, slug: asset.slug)

    assert_empty names(status: "all")
  end

  test "returns empty for a prefix with no tasks" do
    assert_equal [], names(path_prefix: "member/nonexistent").to_a
  end

  test "orders by created_at ascending" do
    travel_to(2.hours.ago) { add("oldest.md", path: "member/ordered") }
    travel_to(1.hour.ago)  { add("middle.md", path: "member/ordered") }
    add("newest.md", path: "member/ordered")

    assert_equal %w[oldest.md middle.md newest.md], names(path_prefix: "member/ordered")
  end

  test "tags filter requires every given tag" do
    add("both.md", tags: %w[urgent backend])
    add("one.md", tags: %w[urgent])
    add("plain.md")

    assert_equal %w[both.md one.md], names(tags: %w[urgent]).sort
    assert_equal [ "both.md" ], names(tags: %w[urgent backend])
    assert_equal [], names(tags: %w[nonexistent])
  end

  test "matches a prefix with hyphens and does not match a sibling that shares the prefix text" do
    add("h.md", path: "member/multi-word-path")
    add("s.md", path: "member/multi-word-path-sibling")

    assert_equal [ "h.md" ], names(path_prefix: "member/multi-word-path")
  end
end
