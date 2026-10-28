require "test_helper"

class VerificationsTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  test "verifying from the show page records it and returns there" do
    asset = create_asset(name: "a.md")
    show = "/member/notes/#{asset.slug}/a.md"

    post "/verifications/#{asset.slug}", headers: { "HTTP_REFERER" => "http://www.example.com#{show}" }

    assert_redirected_to show
    assert_not_nil asset.reload.verified_at
    assert_equal "web", asset.verified_by_agent
  end

  test "a request omitting stale_after leaves the review date alone" do
    asset = create_asset(name: "a.md")
    Assets::SetStaleAfter.mutate(actor: web_actor, slug: asset.slug, stale_after: Date.current - 5)

    post "/verifications/#{asset.slug}"

    assert_equal Date.current - 5, asset.reload.stale_after
  end

  test "an unparseable review date verifies nothing" do
    asset = create_asset(name: "a.md")

    post "/verifications/#{asset.slug}", params: { stale_after: "next tuesday" }

    assert_nil asset.reload.verified_at
    assert_match(/ISO date/, flash[:alert])
  end

  test "cannot verify another member's asset" do
    theirs = create_asset(path: "other/notes", name: "theirs.md", fixture: :other)

    post "/verifications/#{theirs.slug}"

    assert_response :forbidden
    assert_nil theirs.reload.verified_at
  end
end
