require "test_helper"

class TaskTest < ActiveSupport::TestCase
  def asset
    @asset ||= Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/inbox", name: "t.md")
  end

  test "statuses are the five lifecycle states" do
    assert_equal %w[pending in_progress done failed cancelled], Task::STATUSES
  end

  test "a new task is pending with no claim" do
    task = Task.create!(asset:)
    assert_equal "pending", task.status
    assert_nil task.claimed_by_agent
    assert_equal 0, task.attempts
  end

  test "status must be a known lifecycle state" do
    task = Task.new(asset:, status: "open")
    refute task.valid?
  end

  test "the database refuses in_progress without a claimer and lease" do
    assert_raises(ActiveRecord::StatementInvalid) { Task.create!(asset:, status: "in_progress") }
  end

  test "lease_expired? is true only for a lease in the past" do
    task = Task.new(asset:, status: "in_progress", claimed_by_user: users(:member),
                    claimed_by_token: tokens(:member_default), claimed_by_agent: "ping")

    task.lease_until = 1.minute.ago
    assert task.lease_expired?
    task.lease_until = 1.minute.from_now
    refute task.lease_expired?
    task.lease_until = nil
    refute task.lease_expired?
  end
end
