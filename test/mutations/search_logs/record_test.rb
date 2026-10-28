require "test_helper"

class SearchLogs::RecordTest < ActiveSupport::TestCase
  setup { ENV["FOLKLORE_SEARCH_LOG"] = "1" }
  teardown { ENV.delete("FOLKLORE_SEARCH_LOG") }

  test "records the query, filters, result slugs and the token that searched" do
    log = SearchLogs::Record.mutate(actor: actor_for(:member_default), query: "cavoodle",
                                    filters: { "within" => "member/notes", "tags" => %w[pets] },
                                    result_slugs: %w[aaaaaaaa bbbbbbbb])

    assert_equal "cavoodle", log.query
    assert_equal({ "within" => "member/notes", "tags" => %w[pets] }, log.filters)
    assert_equal %w[aaaaaaaa bbbbbbbb], log.result_slugs
    assert_equal tokens(:member_default), log.token
    assert_nil log.followed_slug
  end

  test "a web session's search is recorded without a token" do
    log = SearchLogs::Record.mutate(actor: Actor.for_user(users(:member)), query: "cavoodle", filters: {},
                                    result_slugs: [])

    assert_nil log.token
  end

  test "a blank query is not worth logging" do
    assert_no_difference("SearchLog.count") do
      assert_nil SearchLogs::Record.mutate(actor: actor_for(:member_default), query: "", filters: { "tags" => %w[x] },
                                           result_slugs: [])
    end
  end

  test "logging is off in the test environment unless FOLKLORE_SEARCH_LOG is set" do
    ENV.delete("FOLKLORE_SEARCH_LOG")

    assert_no_difference("SearchLog.count") do
      assert_nil SearchLogs::Record.mutate(actor: actor_for(:member_default), query: "cavoodle", filters: {},
                                           result_slugs: [])
    end
    refute SearchLogs::Record.enabled?
  end
end
