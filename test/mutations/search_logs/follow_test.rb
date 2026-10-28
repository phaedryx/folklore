require "test_helper"

class SearchLogs::FollowTest < ActiveSupport::TestCase
  setup { ENV["FOLKLORE_SEARCH_LOG"] = "1" }
  teardown { ENV.delete("FOLKLORE_SEARCH_LOG") }

  def log(token: tokens(:member_default), slugs: %w[aaaaaaaa bbbbbbbb], created_at: Time.current)
    SearchLog.create!(query: "cavoodle", filters: {}, result_slugs: slugs, token:, created_at:)
  end

  test "marks the most recent log whose results include the slug" do
    older = log(created_at: 2.minutes.ago)
    newer = log(created_at: 1.minute.ago)

    followed = SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "bbbbbbbb")

    assert_equal newer, followed
    assert_equal "bbbbbbbb", newer.reload.followed_slug
    assert_nil older.reload.followed_slug
  end

  test "a read of something the search did not return is not a follow" do
    entry = log

    assert_nil SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "zzzzzzzz")
    assert_nil entry.reload.followed_slug
  end

  test "a search older than five minutes is no longer followed" do
    entry = log(created_at: 6.minutes.ago)

    assert_nil SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "aaaaaaaa")
    assert_nil entry.reload.followed_slug
  end

  test "only the searching token's own logs count" do
    entry = log(token: tokens(:other_default))

    assert_nil SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "aaaaaaaa")
    assert_nil entry.reload.followed_slug
  end

  test "a log already followed is not rewritten by a later read" do
    entry = log
    SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "aaaaaaaa")

    SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "bbbbbbbb")

    assert_equal "aaaaaaaa", entry.reload.followed_slug
  end

  test "a web session has no token to follow from" do
    log(token: nil)

    assert_nil SearchLogs::Follow.mutate(actor: Actor.for_user(users(:member)), slug: "aaaaaaaa")
  end

  test "following is off when logging is off" do
    ENV.delete("FOLKLORE_SEARCH_LOG")
    entry = log

    assert_nil SearchLogs::Follow.mutate(actor: actor_for(:member_default), slug: "aaaaaaaa")
    assert_nil entry.reload.followed_slug
  end
end
