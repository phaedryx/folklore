require "test_helper"

class StaleReviewTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  def overdue(name: "overdue.md", days: 5)
    asset = create_asset(name:, content: "body")
    Assets::SetStaleAfter.mutate(slug: asset.slug, actor: web_actor, stale_after: Date.current - days)
    asset.reload
  end

  test "lists the caller's overdue assets" do
    overdue(name: "overdue.md")
    create_asset(name: "fresh.md", content: "body")

    get stale_path
    assert_response :success
    assert_select "[data-testid='stale-list']"
    assert_match "overdue.md", response.body
    assert_no_match(/fresh\.md/, response.body)
  end

  test "most overdue first" do
    a = overdue(name: "a.md", days: 1)
    b = overdue(name: "b.md", days: 9)

    get stale_path
    ids = css_select("[data-testid^='stale-entry-']").map { |el| el["data-testid"] }
    assert_equal [ "stale-entry-#{b.slug}", "stale-entry-#{a.slug}" ], ids
  end

  test "shows the empty state when nothing is overdue" do
    create_asset(name: "fresh.md", content: "body")

    get stale_path
    assert_select "[data-testid='stale-empty']"
  end

  test "does not list another member's overdue assets" do
    theirs = create_asset(path: "other/notes", name: "theirs.md", content: "b", fixture: :other)
    Assets::SetStaleAfter.mutate(slug: theirs.slug, actor: web_actor(:other), stale_after: Date.current - 1)

    get stale_path
    assert_select "[data-testid='stale-empty']"
  end

  test "redirects unauthenticated requests to sign in" do
    delete sign_out_path

    get stale_path
    assert_redirected_to sign_in_path
  end

  test "verifying from the queue records the verification and the new review date" do
    asset = overdue

    post verify_asset_path(asset.slug), params: { stale_after: (Date.current + 90).iso8601 }

    assert_redirected_to stale_path
    asset.reload
    assert_equal "web", asset.verified_by_agent
    assert_equal Date.current + 90, asset.stale_after
  end

  test "a verified asset with a future review date leaves the queue" do
    asset = overdue

    post verify_asset_path(asset.slug), params: { stale_after: (Date.current + 90).iso8601 }
    get stale_path

    assert_select "[data-testid='stale-empty']"
  end

  test "verifying with the review date cleared removes the asset from the queue for good" do
    asset = overdue

    post verify_asset_path(asset.slug), params: { stale_after: "" }
    get stale_path

    assert_not_nil asset.reload.verified_at
    assert_select "[data-testid='stale-empty']"
    assert_nil asset.reload.stale_after
  end

  test "rejects an unparseable review date without verifying" do
    asset = overdue

    post verify_asset_path(asset.slug), params: { stale_after: "next tuesday" }

    assert_redirected_to stale_path
    assert_nil asset.reload.verified_at
  end
end
