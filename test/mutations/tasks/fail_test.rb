require "test_helper"

class Tasks::FailTest < ActiveSupport::TestCase
  setup do
    @member = actor_for(:member_default)
    @ping = actor_for(:member_default, agent: "ping")
    @pong = actor_for(:member_default, agent: "pong")
    @other = actor_for(:other_default)
  end

  def add_claimed(name, actor: @ping)
    asset = Tasks::Add.mutate(actor: @member, path: "member/inbox", name:, content: "")
    Tasks::Claim.mutate(actor:, slug: asset.slug)
    asset
  end

  def fail_task(asset, actor: @ping, reason: "API timeout")
    Tasks::Fail.mutate(actor:, slug: asset.slug, reason:)
  end

  test "a reason over the length limit is refused before anything changes" do
    asset = add_claimed("long.md")

    error = assert_raises(Tasks::ReasonTooLongError) { fail_task(asset, reason: "r" * (Task::MAX_NOTE_LENGTH + 1)) }

    assert_equal "reason is 10001 characters, over the 10000 character limit", error.message
    assert_equal "in_progress", asset.reload.task.status
  end

  test "fails a task the actor holds with a reason, clearing the claimer and lease" do
    asset = add_claimed("f1.md")

    task = fail_task(asset).task

    assert_equal "failed", task.status
    assert_nil task.claimed_by_user_id
    assert_nil task.claimed_by_agent
    assert_nil task.lease_until
    assert_equal "API timeout", task.outcome_note
  end

  test "records the stripped reason in the task_failed event" do
    asset = add_claimed("f2.md")

    fail_task(asset, reason: "  retries exhausted  ")

    event = Event.where(asset_id: asset.id, action: "task_failed").sole
    assert_equal "ping", event.actor_agent
    assert_equal({ "reason" => "retries exhausted" }, event.metadata)
    assert_equal "retries exhausted", asset.task.reload.outcome_note
  end

  test "requires a reason" do
    asset = add_claimed("f3.md")

    assert_raises(Tasks::ReasonRequiredError) { fail_task(asset, reason: nil) }
    assert_raises(Tasks::ReasonRequiredError) { fail_task(asset, reason: "   ") }
    assert_equal "in_progress", asset.task.reload.status
  end

  test "the finisher failing again is idempotent and keeps the first reason" do
    asset = add_claimed("f4.md")
    fail_task(asset, reason: "first reason")

    result = fail_task(asset, reason: "second reason")

    assert_equal "failed", result.task.status
    events = Event.where(asset_id: asset.id, action: "task_failed")
    assert_equal 1, events.count
    assert_equal "first reason", events.first.metadata["reason"]
  end

  test "another agent on the same token, another member, and a non-finisher on a failed task are wrong claimers" do
    asset = add_claimed("f5.md")

    assert_raises(Tasks::WrongClaimerError) { fail_task(asset, actor: @pong) }
    assert_raises(Tasks::WrongClaimerError) { fail_task(asset, actor: @other) }

    fail_task(asset)
    assert_raises(Tasks::WrongClaimerError) { fail_task(asset, actor: @pong) }
  end

  test "another token acting as the holder's agent is a wrong claimer" do
    asset = add_claimed("f-token.md", actor: actor_for(:member_writeonly))
    impostor = actor_for(:member_default, agent: "writer")

    assert_raises(Tasks::WrongClaimerError) { fail_task(asset, actor: impostor) }

    assert_equal "in_progress", asset.task.reload.status
  end

  test "another token acting as the finisher's agent is not answered as the finisher" do
    asset = add_claimed("f-token-2.md", actor: actor_for(:member_writeonly))
    fail_task(asset, actor: actor_for(:member_writeonly))
    impostor = actor_for(:member_default, agent: "writer")

    assert_raises(Tasks::WrongClaimerError) { fail_task(asset, actor: impostor) }
  end

  test "a failed task can be claimed again? no: it is finished" do
    asset = add_claimed("f6.md")
    fail_task(asset)

    assert_raises(Tasks::AlreadyClaimedError) { Tasks::Claim.mutate(actor: @pong, slug: asset.slug) }
  end

  test "raises NotATaskError for a note and NotFoundError for an unknown slug" do
    note = Assets::Create.mutate(actor: @member, path: "member/notes", name: "n.md", content: "")

    assert_raises(Tasks::NotATaskError) { fail_task(note) }
    assert_raises(Assets::NotFoundError) { Tasks::Fail.mutate(actor: @ping, slug: "00000000", reason: "x") }
  end
end
