require "application_system_test_case"

class HubFlowTest < ApplicationSystemTestCase
  setup do
    @member = users(:member)
    sign_in(@member, password: "member-secret")
  end

  test "create file lands on the asset show page with the new content" do
    visit workspace_path(handle: "member", location: "dad-jokes")
    click_on "New file"
    assert_current_path new_file_path(path: "member/dad-jokes")
    fill_in "Name", with: "jokes.sh"
    fill_in "Content", with: "echo hello"
    fill_in "Tags", with: "shell, onboarding"
    click_on "Create"

    assert_selector "[data-testid='asset-content']", text: "echo hello"
    assert_no_selector "[data-testid='tag-chip']"
    assert_equal %w[onboarding shell], Asset.find_by!(name: "jokes.sh").tags.map(&:name).sort
  end

  test "created file appears in the file browser at its location" do
    asset = create_asset(path: "member/dad-jokes", name: "jokes.sh", content: "echo hello")

    visit workspace_path(handle: "member", location: "dad-jokes")
    assert_selector "[data-testid='file-row-#{asset.slug}']", text: "jokes.sh"
  end

  test "search finds the file by content" do
    create_asset(path: "member/dad-jokes", name: "jokes.sh", content: "echo something distinctive")

    within("[data-testid='primary-nav']") { click_on "Search" }
    fill_in "Query", with: "distinctive"
    click_button "Search"
    within("[data-testid='search-results']") { assert_link "jokes.sh" }
  end

  test "the review queue verifies an overdue file and it leaves the queue" do
    asset = create_asset(path: "member/notes", name: "old.md", content: "x")
    Assets::SetStaleAfter.mutate(actor: web_actor, slug: asset.slug, stale_after: Date.current - 3)

    click_on "Review"
    assert_selector "[data-testid='stale-entry-#{asset.slug}']", text: "3 days overdue"
    find("[data-testid='stale-verify-#{asset.slug}']").click

    assert_selector "[data-testid='flash-notice']", text: "Verified."
    assert_selector "[data-testid='stale-empty']"
  end

  test "the activity page shows what was just done" do
    asset = create_asset(path: "member/notes", name: "fresh.md", content: "x")

    click_on "Activity"
    assert_selector "[data-testid^='activity-asset-']", text: asset.name
  end

  test "archive from the file browser removes the file then restore brings it back" do
    asset = create_asset(path: "member/notes", name: "delete-me.md", content: "bye")

    visit workspace_path(handle: "member", location: "notes")
    find("[data-testid='file-archive-#{asset.slug}']").click

    assert_no_selector "[data-testid='file-row-#{asset.slug}']"

    visit workspace_archive_path("member")
    assert_selector "[data-testid='archive-asset-#{asset.slug}']"

    find("[data-testid='restore-#{asset.slug}']").click
    assert_current_path workspace_path("member")

    visit workspace_path(handle: "member", location: "notes")
    assert_selector "[data-testid='file-row-#{asset.slug}']"
  end

  test "following a wikilink and the backlink round-trips between two files" do
    target = create_asset(path: "member/notes", name: "target.md", content: "the target")
    create_asset(path: "member/notes", name: "source.md", content: "see [[#{target.slug}]]")

    visit workspace_path(handle: "member", location: "notes")
    click_on "source.md"
    within("[data-testid='asset-content']") { click_on "target.md" }
    assert_selector "[data-testid='asset-content']", text: "the target"

    within("[data-testid='backlinks']") { click_on "source.md" }
    assert_selector "[data-testid='asset-content']", text: "see target.md"
  end
end
