require "test_helper"

class Tasks::ClaimTest < ActiveSupport::TestCase
  setup do
    @member = actor_for(:member_default)
    @ping = actor_for(:member_default, agent: "ping")
    @pong = actor_for(:member_default, agent: "pong")
    @other = actor_for(:other_default)
  end

  def add(name, path: "member/inbox", tags: [])
    Tasks::Add.mutate(actor: @member, path:, name:, content: "", tags:)
  end

  def claim(asset, actor: @member, **args)
    Tasks::Claim.mutate(actor:, slug: asset.slug, **args)
  end

  def actions(asset)
    Event.where(asset_id: asset.id).order(:id).pluck(:action)
  end

  test "claims a pending task for the actor's (user, agent) with a 30 minute lease" do
    asset = add("task.md")

    claimed = claim(asset, actor: @ping)

    task = claimed.task
    assert_equal "in_progress", task.status
    assert_equal @ping.user.id, task.claimed_by_user_id
    assert_equal @ping.token.id, task.claimed_by_token_id
    assert_equal "ping", task.claimed_by_agent
    assert_in_delta 30.minutes.from_now, task.lease_until, 5.seconds
    assert_equal 1, task.attempts
  end

  test "writes a task_claimed event stamped with the claiming agent" do
    asset = add("task.md")

    claim(asset, actor: @ping)

    event = Event.where(asset_id: asset.id, action: "task_claimed").sole
    assert_equal @ping.user.id, event.actor_user_id
    assert_equal "ping", event.actor_agent
  end

  test "lease_seconds sets the lease length and must be a positive integer" do
    asset = add("task.md")

    claimed = claim(asset, lease_seconds: 60)
    assert_in_delta 60.seconds.from_now, claimed.task.lease_until, 5.seconds

    [ 0, -5, "soon", 1.5 ].each do |bad|
      assert_raises(Tasks::InvalidLeaseError, bad.inspect) { claim(add("bad-#{bad}.md"), lease_seconds: bad) }
    end
  end

  test "the holder re-claiming renews the lease without a second event or attempt" do
    asset = add("task.md")
    claim(asset, actor: @ping, lease_seconds: 60)

    renewed = travel(30.seconds) { claim(asset, actor: @ping, lease_seconds: 60) }

    assert_equal "in_progress", renewed.task.status
    assert_in_delta 90.seconds.from_now, renewed.task.lease_until, 5.seconds
    assert_equal 1, renewed.task.attempts
    assert_equal [ "task_added", "task_claimed" ], actions(asset)
  end

  # Review Focus 1: two agents on one token are two claimers.
  test "a second agent on the same token cannot claim a task the first holds" do
    asset = add("task.md")
    claim(asset, actor: @ping)

    error = assert_raises(Tasks::AlreadyClaimedError) { claim(asset, actor: @pong) }

    assert_match(/claimed by member\/ping until/, error.message)
    assert_equal "ping", asset.task.reload.claimed_by_agent
    assert_equal [ "task_added", "task_claimed" ], actions(asset)
  end

  test "another member cannot claim a held task" do
    asset = add("task.md")
    claim(asset)

    assert_raises(Tasks::AlreadyClaimedError) { claim(asset, actor: @other) }
  end

  # Review Focus 2: an expired lease is reclaimable, an unexpired one is not.
  test "an expired lease is reclaimable by another agent and records task_lease_expired" do
    asset = add("task.md")
    claim(asset, actor: @ping, lease_seconds: 1)
    expired_at = asset.task.reload.lease_until

    assert_raises(Tasks::AlreadyClaimedError) { claim(asset, actor: @pong) }

    reclaimed = travel(2.seconds) { claim(asset, actor: @pong) }

    task = reclaimed.task
    assert_equal "pong", task.claimed_by_agent
    assert_equal 2, task.attempts
    assert_equal [ "task_added", "task_claimed", "task_lease_expired", "task_claimed" ], actions(asset)

    expired = Event.where(asset_id: asset.id, action: "task_lease_expired").sole
    assert_equal "pong", expired.actor_agent
    assert_equal({ "claimed_by" => "member/ping", "lease_until" => expired_at.iso8601 }, expired.metadata)
  end

  test "the holder re-claiming its own expired lease just renews it" do
    asset = add("task.md")
    claim(asset, actor: @ping, lease_seconds: 1)

    travel(2.seconds) { claim(asset, actor: @ping) }

    assert_equal 1, asset.task.reload.attempts
    assert_equal [ "task_added", "task_claimed" ], actions(asset)
  end

  test "a finished task cannot be claimed" do
    asset = add("task.md")
    claim(asset)
    Tasks::Complete.mutate(actor: @member, slug: asset.slug)

    error = assert_raises(Tasks::AlreadyClaimedError) { claim(asset, actor: @pong) }
    assert_match(/is done/, error.message)
  end

  test "a web actor can claim: the claim records the user and agent with no token" do
    asset = add("task.md")

    claimed = claim(asset, actor: Actor.for_user(users(:member)))

    assert_nil claimed.task.claimed_by_token_id
    assert_equal "web", claimed.task.claimed_by_agent
  end

  test "raises NotATaskError for a note" do
    note = Assets::Create.mutate(actor: @member, path: "member/notes", name: "n.md", content: "")

    assert_raises(Tasks::NotATaskError) { claim(note) }
  end

  test "raises NotFoundError for an unknown or deleted slug" do
    assert_raises(Assets::NotFoundError) { Tasks::Claim.mutate(actor: @member, slug: "00000000") }

    gone = add("gone.md")
    Assets::Delete.mutate(actor: @member, slug: gone.slug)
    assert_raises(Assets::NotFoundError) { claim(gone) }
  end

  # Next-pending mode: no slug, a path prefix.

  test "without a slug claims the oldest eligible task under the prefix" do
    travel_to(2.hours.ago) { add("oldest.md", path: "member/backlog") }
    travel_to(1.hour.ago) { add("middle.md", path: "member/backlog") }
    add("newest.md", path: "member/backlog")
    add("elsewhere.md", path: "member/other")

    first = Tasks::Claim.mutate(actor: @ping, path_prefix: "member/backlog")
    second = Tasks::Claim.mutate(actor: @ping, path_prefix: "member/backlog")

    assert_equal %w[oldest.md middle.md], [ first.name, second.name ]
    assert_equal "ping", first.task.claimed_by_agent
    assert_equal [ "task_added", "task_claimed" ], actions(first)
  end

  test "without a slug honours tags and skips tasks held on an unexpired lease" do
    held = add("held.md", path: "member/backlog", tags: %w[urgent])
    claim(held, actor: @pong)
    add("plain.md", path: "member/backlog")
    urgent = add("urgent.md", path: "member/backlog", tags: %w[urgent])

    claimed = Tasks::Claim.mutate(actor: @ping, path_prefix: "member/backlog", tags: %w[urgent])

    assert_equal urgent.id, claimed.id
  end

  test "without a slug picks up a task whose lease expired, recording the expiry" do
    stale = add("stale.md", path: "member/backlog")
    claim(stale, actor: @pong, lease_seconds: 1)

    claimed = travel(2.seconds) { Tasks::Claim.mutate(actor: @ping, path_prefix: "member/backlog") }

    assert_equal stale.id, claimed.id
    assert_equal [ "task_added", "task_claimed", "task_lease_expired", "task_claimed" ], actions(stale)
  end

  test "without a slug raises NoPendingTaskError when nothing is eligible" do
    held = add("held.md", path: "member/backlog")
    claim(held, actor: @pong)

    assert_raises(Tasks::NoPendingTaskError) { Tasks::Claim.mutate(actor: @ping, path_prefix: "member/backlog") }
    assert_raises(Tasks::NoPendingTaskError) { Tasks::Claim.mutate(actor: @ping, path_prefix: "member/empty") }
  end

  test "requires a slug or a path_prefix" do
    assert_raises(Tasks::InvalidArgumentError) { Tasks::Claim.mutate(actor: @ping) }
  end
end
