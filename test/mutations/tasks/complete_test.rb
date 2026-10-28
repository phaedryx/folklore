require "test_helper"

class Tasks::CompleteTest < ActiveSupport::TestCase
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

  def complete(asset, actor: @ping, **args)
    Tasks::Complete.mutate(actor:, slug: asset.slug, **args)
  end

  test "completes a task the actor holds, clearing the claimer and lease" do
    asset = add_claimed("c1.md")

    task = complete(asset).task

    assert_equal "done", task.status
    assert_nil task.claimed_by_user_id
    assert_nil task.claimed_by_token_id
    assert_nil task.claimed_by_agent
    assert_nil task.lease_until
    assert_nil task.outcome_note
  end

  test "writes a task_completed event from the finisher, carrying the note" do
    asset = add_claimed("c2.md")

    complete(asset, note: "shipped in 3 commits")

    event = Event.where(asset_id: asset.id, action: "task_completed").sole
    assert_equal @ping.user.id, event.actor_user_id
    assert_equal "ping", event.actor_agent
    assert_equal({ "note" => "shipped in 3 commits" }, event.metadata)
    assert_equal "shipped in 3 commits", asset.task.reload.outcome_note
  end

  test "a finished task keeps no claimer: the database refuses one" do
    asset = add_claimed("c3.md")
    complete(asset)

    assert_raises(ActiveRecord::StatementInvalid) do
      asset.task.reload.update_columns(claimed_by_user_id: @member.user.id, claimed_by_agent: "ping")
    end
  end

  test "the finisher completing again is idempotent" do
    asset = add_claimed("c4.md")
    complete(asset, note: "first")

    result = complete(asset, note: "second")

    assert_equal "done", result.task.status
    assert_equal "first", result.task.outcome_note
    assert_equal 1, Event.where(asset_id: asset.id, action: "task_completed").count
  end

  test "another agent on the same token is a wrong claimer" do
    asset = add_claimed("c5.md")

    assert_raises(Tasks::WrongClaimerError) { complete(asset, actor: @pong) }
    assert_equal "in_progress", asset.task.reload.status
  end

  test "another member is a wrong claimer, and so is anyone completing a done task they did not finish" do
    asset = add_claimed("c6.md")
    assert_raises(Tasks::WrongClaimerError) { complete(asset, actor: @other) }

    complete(asset)
    assert_raises(Tasks::WrongClaimerError) { complete(asset, actor: @pong) }
  end

  test "a pending task has no claimer to complete it" do
    asset = Tasks::Add.mutate(actor: @member, path: "member/inbox", name: "c7.md", content: "")

    assert_raises(Tasks::WrongClaimerError) { complete(asset) }
  end

  test "the holder may complete after its lease expired, as long as nobody reclaimed" do
    asset = Tasks::Add.mutate(actor: @member, path: "member/inbox", name: "c8.md", content: "")
    Tasks::Claim.mutate(actor: @ping, slug: asset.slug, lease_seconds: 1)

    travel(2.seconds) { complete(asset) }

    assert_equal "done", asset.task.reload.status
  end

  test "a holder whose expired lease was reclaimed is a wrong claimer" do
    asset = Tasks::Add.mutate(actor: @member, path: "member/inbox", name: "c9.md", content: "")
    Tasks::Claim.mutate(actor: @ping, slug: asset.slug, lease_seconds: 1)
    travel(2.seconds) { Tasks::Claim.mutate(actor: @pong, slug: asset.slug) }

    assert_raises(Tasks::WrongClaimerError) { complete(asset) }
    assert_equal "done", complete(asset, actor: @pong).task.status
  end

  test "raises NotATaskError for a note and NotFoundError for an unknown slug" do
    note = Assets::Create.mutate(actor: @member, path: "member/notes", name: "n.md", content: "")

    assert_raises(Tasks::NotATaskError) { complete(note) }
    assert_raises(Assets::NotFoundError) { Tasks::Complete.mutate(actor: @ping, slug: "00000000") }
  end
end
