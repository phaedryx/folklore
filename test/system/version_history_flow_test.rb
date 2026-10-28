require "application_system_test_case"

class VersionHistoryFlowTest < ApplicationSystemTestCase
  test "owner sees a diff and can restore an older version" do
    asset = create_asset(name: "hello.md", content: "v1")
    Assets::Update.mutate(slug: asset.slug, actor: web_actor, content: "v2")
    version = asset.versions.order(:created_at).first

    sign_in(users(:member), password: "member-secret")
    visit workspace_path(handle: "member", location: "notes")
    click_on "hello.md"
    click_on "History"

    assert_selector "[data-testid='version-diff-#{version.id}'] [data-diff-side='old'] .diff-removed", text: "v1"
    assert_selector "[data-testid='version-diff-#{version.id}'] [data-diff-side='new'] .diff-added", text: "v2"

    click_on "Restore this version"

    assert_selector "[data-testid='flash-notice']", text: "Version restored."
    assert_selector "[data-testid='version-head']", text: "v1"
    assert_equal "v1", asset.reload.content
  end

  test "a non-owner viewing another workspace sees no restore button" do
    asset = create_asset(name: "hello.md", content: "v1")
    Assets::Update.mutate(slug: asset.slug, actor: web_actor, content: "v2")

    sign_in(users(:other))
    visit "/member/notes/#{asset.slug}/hello.md/versions"

    assert_selector "[data-testid='version-head']"
    assert_no_button "Restore this version"
  end
end
