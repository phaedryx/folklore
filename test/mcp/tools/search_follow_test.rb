require "test_helper"

# A read of a search result marks the search as answered, so the search log
# can grow the eval set. Wired into read.
class FolkloreMcp::Tools::SearchFollowTest < ActiveSupport::TestCase
  setup { ENV["FOLKLORE_SEARCH_LOG"] = "1" }
  teardown { ENV.delete("FOLKLORE_SEARCH_LOG") }

  def search_for_needle
    asset = ::Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "needle.md", content: "haystack")
    FolkloreMcp::Tools::Search::Search.call(q: "haystack", server_context: actor_context)
    asset
  end

  test "read of a search result follows the search" do
    asset = search_for_needle

    response = FolkloreMcp::Tools::Assets::Read.call(ref: asset.slug, server_context: actor_context)

    refute response.to_h[:isError]
    assert_equal asset.slug, SearchLog.sole.followed_slug
  end

  test "read by location of a search result follows the search" do
    asset = search_for_needle

    FolkloreMcp::Tools::Assets::Read.call(ref: asset.location, server_context: actor_context)

    assert_equal asset.slug, SearchLog.sole.followed_slug
  end

  test "a search is followed only by a read from the agent that searched" do
    asset = ::Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "needle.md", content: "haystack")
    FolkloreMcp::Tools::Search::Search.call(q: "haystack", server_context: actor_context(agent: "ping"))
    assert_equal "ping", SearchLog.sole.actor_agent

    FolkloreMcp::Tools::Assets::Read.call(ref: asset.slug, server_context: actor_context(agent: "pong"))
    assert_nil SearchLog.sole.followed_slug

    FolkloreMcp::Tools::Assets::Read.call(ref: asset.slug, server_context: actor_context(agent: "ping"))
    assert_equal asset.slug, SearchLog.sole.followed_slug
  end

  test "a failed read follows nothing" do
    search_for_needle

    FolkloreMcp::Tools::Assets::Read.call(ref: "zzzzzzzz", server_context: actor_context)

    assert_nil SearchLog.sole.followed_slug
  end

  test "a search-log failure does not fail the search" do
    ::Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "needle.md", content: "haystack")

    SearchLogs::Record.singleton_class.alias_method(:original_mutate, :mutate)
    SearchLogs::Record.define_singleton_method(:mutate) { |**| raise ActiveRecord::StatementInvalid, "boom" }

    response = FolkloreMcp::Tools::Search::Search.call(q: "haystack", server_context: actor_context)

    refute response.to_h[:isError], text_of(response)
    assert_match(/needle\.md/, text_of(response))
  ensure
    SearchLogs::Record.singleton_class.alias_method(:mutate, :original_mutate)
  end

  test "a search-log failure does not fail the read" do
    asset = search_for_needle

    SearchLogs::Follow.singleton_class.alias_method(:original_mutate, :mutate)
    SearchLogs::Follow.define_singleton_method(:mutate) { |**| raise ActiveRecord::StatementInvalid, "boom" }

    response = FolkloreMcp::Tools::Assets::Read.call(ref: asset.slug, server_context: actor_context)

    refute response.to_h[:isError]
    assert_equal "haystack", response.to_h[:structuredContent][:content]
  ensure
    SearchLogs::Follow.singleton_class.alias_method(:mutate, :original_mutate)
  end
end
