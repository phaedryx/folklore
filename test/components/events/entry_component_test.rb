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
end
