require "test_helper"

class Events::ListTest < ActiveSupport::TestCase
  def asset(name = "a.md", owner: users(:member))
    Asset.create!(owner:, slug: Asset.generate_slug, dir: "#{owner.handle}/notes", name:)
  end

  def record(action: "asset_created", actor: actor_for(:member_default), asset: nil, at: nil)
    event = Events::Record.mutate(actor:, action:, asset:)
    event.update_column(:created_at, at) if at
    event
  end

  test "returns recent events, newest first" do
    record(at: 2.hours.ago)
    record(at: 1.hour.ago)

    timestamps = Events::List.query.map(&:created_at)

    assert_equal 2, timestamps.size
    assert_equal timestamps.sort.reverse, timestamps
  end

  test "filters by actor handle" do
    record(actor: actor_for(:member_default))
    record(actor: actor_for(:other_default))

    results = Events::List.query(actor: "other")

    assert_equal 1, results.size
    assert results.all? { |e| e.actor_user_id == users(:other).id }
  end

  test "filters by handle/agent" do
    record(actor: actor_for(:member_default, agent: "ping"))
    record(actor: actor_for(:member_default, agent: "pong"))

    results = Events::List.query(actor: "member/pong")

    assert_equal [ "pong" ], results.map(&:actor_agent)
  end

  test "an unknown handle matches nothing" do
    record

    assert_empty Events::List.query(actor: "nobody")
  end

  test "filters by tag" do
    tagged = asset("tagged.md")
    untagged = asset("untagged.md")
    AssetTag.create!(asset: tagged, tag: Tag.create!(name: "todo"))
    record(asset: tagged)
    record(asset: untagged)

    asset_ids = Events::List.query(tag: "TODO ").map(&:asset_id)

    assert_includes asset_ids, tagged.id
    refute_includes asset_ids, untagged.id
  end

  test "since and before bound the window" do
    earlier = record(at: 2.hours.ago)
    later = record(at: 1.hour.ago)
    cutoff = 90.minutes.ago

    assert_equal [ later ], Events::List.query(since: cutoff).to_a
    assert_equal [ earlier ], Events::List.query(before: cutoff).to_a
  end

  test "since_id returns the events after a cursor, oldest first" do
    first = record
    second = record
    third = record

    assert_equal [ second, third ], Events::List.query(since_id: first.id).to_a
  end

  test "before_id returns the events before a cursor, newest first" do
    first = record
    second = record
    third = record

    assert_equal [ second, first ], Events::List.query(before_id: third.id).to_a
  end

  test "limit caps results and is itself capped" do
    3.times { record }

    assert_equal 1, Events::List.query(limit: 1).count
    assert_equal Events::List::MAX_LIMIT, Events::List.query(limit: 99_999).limit_value
    assert_equal Events::List::DEFAULT_LIMIT, Events::List.query(limit: 0).limit_value
  end
end
