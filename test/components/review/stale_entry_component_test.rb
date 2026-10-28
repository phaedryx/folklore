require "test_helper"

class Review::StaleEntryComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  def overdue(days:)
    asset = create_asset(name: "old.md")
    Assets::SetStaleAfter.mutate(actor: web_actor, slug: asset.slug, stale_after: Date.current - days)
    asset.reload
  end

  test "says how overdue it is and links to the asset" do
    asset = overdue(days: 5)

    render_inline Review::StaleEntryComponent.new(asset:)

    assert_selector "[data-testid='stale-entry-#{asset.slug}'] [data-testid='stale-marker']", text: "5 days overdue"
    assert_selector "a[href='/member/notes/#{asset.slug}/old.md']", text: "old.md"
  end

  test "one day is singular" do
    render_inline Review::StaleEntryComponent.new(asset: overdue(days: 1))

    assert_selector "[data-testid='stale-marker']", text: "1 day overdue"
  end

  test "says never verified, or when and by whom" do
    asset = overdue(days: 2)
    render_inline Review::StaleEntryComponent.new(asset:)
    assert_text "never verified"

    Assets::Verify.mutate(actor: actor_for(:member_default, agent: "ping"), slug: asset.slug)
    render_inline Review::StaleEntryComponent.new(asset: asset.reload)
    assert_text "verified #{Date.current.to_fs(:long)} by member/ping"
  end

  test "posts a verify with a pre-filled next review date ninety days out" do
    asset = overdue(days: 2)

    render_inline Review::StaleEntryComponent.new(asset:)

    assert_selector "form[action='/verifications/#{asset.slug}'] input[type=date][name=stale_after][value='#{(Date.current + 90).iso8601}']"
    assert_selector "[data-testid='stale-verify-#{asset.slug}']"
  end
end
