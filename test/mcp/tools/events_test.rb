require "test_helper"

class FolkloreMcp::Tools::EventsTest < ActiveSupport::TestCase
  Activity = FolkloreMcp::Tools::Events::Activity

  test "activity is registered, read-only, with an output schema" do
    assert_equal "activity", Activity.name_value
    assert Activity.to_h[:annotations][:readOnlyHint]
    assert Activity.to_h[:outputSchema]
  end

  test "activity lists recent events newest first as text lines and structured rows" do
    asset = ::Assets::Create.mutate(actor: actor_for(:member_default, agent: "ping"), path: "member/notes", name: "feed.md", content: "")
    ::Tags::Apply.mutate(actor: actor_for(:member_default, agent: "ping"), slug: asset.slug, tag: "todo")

    response = Activity.call(limit: 5, server_context: actor_context)

    refute response.to_h[:isError], text_of(response)
    lines = text_of(response).lines(chomp: true)
    assert_equal 3, lines.size
    assert_match(/\A\d{4}-\d{2}-\d{2}T\S+  member\/ping  asset_updated  #{asset.slug}\z/, lines[0])
    assert_match(/  member\/ping  tag_added  #{asset.slug}  tag: todo\z/, lines[1])
    assert_match(/  member\/ping  asset_created  #{asset.slug}\z/, lines[2])
    rows = response.to_h[:structuredContent][:events]
    assert_equal "tag_added", rows[1][:action]
    assert_equal({ handle: "member", agent: "ping" }, rows[1][:actor])
    assert_equal({ "tag" => "todo" }, rows[1][:metadata])
    assert_equal asset.slug, rows[1][:slug]
  end

  test "activity filters by actor handle/agent, tag, since and since_id" do
    ping = actor_for(:member_default, agent: "ping")
    pong = actor_for(:member_default, agent: "pong")
    a = ::Assets::Create.mutate(actor: ping, path: "member/notes", name: "a.md", content: "", tags: %w[todo])
    first_id = Event.maximum(:id)
    ::Assets::Create.mutate(actor: pong, path: "member/notes", name: "b.md", content: "")

    by_agent = Activity.call(actor: "member/pong", server_context: actor_context)
    assert_equal 1, text_of(by_agent).lines.size
    assert_match(/member\/pong/, text_of(by_agent))

    by_tag = Activity.call(tag: "todo", server_context: actor_context)
    assert text_of(by_tag).lines.all? { |l| l.include?(a.slug) }

    after = Activity.call(since_id: first_id, server_context: actor_context)
    assert_equal 1, text_of(after).lines.size
    assert_match(/asset_created/, text_of(after))

    nothing = Activity.call(since: 1.hour.from_now.iso8601, server_context: actor_context)
    assert_equal "No activity", text_of(nothing)
    assert_equal [], nothing.to_h[:structuredContent][:events]
  end

  test "activity accepts a date-only since, read in the app time zone" do
    ::Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "a.md", content: "")

    response = Activity.call(since: Date.current.iso8601, server_context: actor_context)

    refute response.to_h[:isError], text_of(response)
    assert_match(/asset_created/, text_of(response))
    assert_equal "No activity", text_of(Activity.call(since: Date.tomorrow.iso8601, server_context: actor_context))
  end

  test "activity rejects an unparseable timestamp" do
    response = Activity.call(since: "yesterday-ish", server_context: actor_context)

    assert response.to_h[:isError]
    assert_match(/\AInvalid \[[a-z_]+\]: since/, text_of(response))
  end

  test "activity accepts a space-separated time, an email actor, and defaults to 50 events" do
    actor = actor_for(:member_default, agent: "ping")
    asset = ::Assets::Create.mutate(actor:, path: "member/notes", name: "many.md", content: "")
    60.times { |i| ::Events::Record.mutate(actor:, asset:, action: "tag_added", metadata: { "tag" => "t#{i}" }) }

    assert_equal 50, text_of(Activity.call(server_context: actor_context)).lines.size
    assert_equal 50, text_of(Activity.call(actor: "MEMBER@example.com", server_context: actor_context)).lines.size
    spaced = Activity.call(since: 1.hour.ago.strftime("%Y-%m-%d %H:%M:%S"), limit: 200, server_context: actor_context)
    refute spaced.to_h[:isError], text_of(spaced)
    assert_equal 61, text_of(spaced).lines.size
  end

  test "activity rejects a non-numeric since_id" do
    response = Activity.call(since_id: "abc", server_context: actor_context)

    assert response.to_h[:isError]
    assert_equal "Invalid [invalid_cursor]: since_id must be a non-negative integer, got \"abc\"", text_of(response)
  end
end
