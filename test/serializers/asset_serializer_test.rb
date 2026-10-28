require "test_helper"

class AssetSerializerTest < ActiveSupport::TestCase
  test "serializes an asset with its actors, task and tags" do
    token = tokens(:member_default)
    asset = Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name: "a.md",
                          content: "body", content_type: "text/markdown", status: "open",
                          stale_after: Date.new(2026, 12, 1),
                          created_by_token: token, created_by_agent: "ping",
                          updated_by_token: token, updated_by_agent: "pong")
    AssetTag.create!(asset:, tag: Tag.create!(name: "ruby"))

    data = AssetSerializer.call(asset)

    assert_equal asset.slug, data[:slug]
    assert_equal "a.md", data[:name]
    assert_equal "body", data[:content]
    assert_equal "text/markdown", data[:content_type]
    assert_equal "open", data[:status]
    assert_equal "member", data[:owner_handle]
    assert_equal "member/notes", data[:path]
    assert_equal "member/notes", data[:dir]
    assert_equal "member/notes/a.md", data[:location]
    assert_equal [ "ruby" ], data[:tags]
    assert_equal 0, data[:version]
    assert_equal "2026-12-01", data[:stale_after]
    assert_nil data[:verified_at]
    assert_equal({ handle: "member", agent: "ping" }, data[:created_by])
    assert_equal({ handle: "member", agent: "pong" }, data[:updated_by])
    assert_nil data[:verified_by]
    assert_nil data[:task]
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, data[:created_at])
  end

  test "a web write records the owner as the actor with the web agent and no token" do
    asset = Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name: "a.md",
                          created_by_agent: "web", verified_at: Time.current, verified_by_agent: "web")

    data = AssetSerializer.call(asset)

    assert_equal({ handle: "member", agent: "web" }, data[:created_by])
    assert_equal({ handle: "member", agent: "web" }, data[:verified_by])
    assert_nil data[:updated_by]
  end

  test "a task asset carries its facet" do
    asset = Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/inbox", name: "t.md")
    Task.create!(asset:, status: "in_progress", claimed_by_user: users(:member),
                 claimed_by_token: tokens(:member_default), claimed_by_agent: "ping", lease_until: 10.minutes.from_now)

    task = AssetSerializer.call(asset)[:task]

    assert_equal "in_progress", task[:status]
    assert_equal "member/ping", task[:claimed_by]
    assert_match(/\A\d{4}-/, task[:lease_until])
  end
end
