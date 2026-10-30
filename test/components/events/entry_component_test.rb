require "test_helper"

class Events::EntryComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "shows actor as handle/agent, the action and a link to a live asset" do
    asset = create_asset(name: "n.md")
    event = Events::Record.mutate(actor: actor_for(:member_default, agent: "ping"), asset:, action: "asset_verified")

    render_inline Events::EntryComponent.new(event:)

    assert_selector "[data-testid='activity-#{event.id}']"
    assert_selector "[data-testid='activity-actor-#{event.id}'][href='/activity?actor=member%2Fping']", text: "member/ping"
    assert_selector "[data-testid='activity-action-#{event.id}']", text: "asset_verified"
    assert_selector "[data-testid='activity-asset-#{event.id}'][href='/member/notes/#{asset.slug}/n.md']", text: "n.md"
  end

  test "an archived asset is named but not linked" do
    asset = create_asset(name: "gone.md")
    Assets::Delete.mutate(actor: web_actor, slug: asset.slug)
    event = Event.where(asset:, action: "asset_deleted").sole

    render_inline Events::EntryComponent.new(event:)

    assert_selector "[data-testid='activity-asset-#{event.id}']", text: "gone.md (archived)"
    assert_no_selector "a[data-testid='activity-asset-#{event.id}']"
  end

  test "shows the tag, note or reason the event carries" do
    asset = create_asset(name: "n.md")
    event = Events::Record.mutate(actor: web_actor, asset:, action: "tag_added", metadata: { "tag" => "shell" })

    render_inline Events::EntryComponent.new(event:)

    assert_selector "[data-testid='activity-detail-#{event.id}']", text: "shell"
  end

  test "reads a renewal, an expired lease and a cleared review date as such" do
    asset = create_asset(name: "t.md")
    renewal = Events::Record.mutate(actor: web_actor, asset:, action: "task_claimed",
                                    metadata: { "lease_until" => "2026-10-28T16:00:00Z", "renewal" => true })
    expired = Events::Record.mutate(actor: web_actor, asset:, action: "task_lease_expired",
                                    metadata: { "claimed_by" => "member/ping", "lease_until" => "2026-10-28T15:00:00Z" })
    cleared = Events::Record.mutate(actor: web_actor, asset:, action: "asset_review_scheduled", metadata: { "stale_after" => nil })

    assert_equal "renewal · lease until 2026-10-28T16:00:00Z", Events::Detail.call(renewal)
    assert_equal "member/ping's lease ended 2026-10-28T15:00:00Z", Events::Detail.call(expired)
    assert_equal "review after: cleared", Events::Detail.call(cleared)

    render_inline Events::EntryComponent.new(event: expired)
    assert_selector "[data-testid='activity-detail-#{expired.id}']", text: "member/ping's lease ended"
  end

  test "a deleted task names the claim it released" do
    asset = create_asset(name: "t.md")
    deleted = Events::Record.mutate(actor: web_actor, asset:, action: "asset_deleted", metadata: { "released_claim" => "member/ping" })

    assert_equal "released member/ping's claim", Events::Detail.call(deleted)
  end
end
