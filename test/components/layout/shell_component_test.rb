require "test_helper"

class Layout::ShellComponentTest < ViewComponent::TestCase
  test "signed out shows the brand and no primary nav" do
    render_inline(Layout::ShellComponent.new(current_user: nil)) { "body" }

    assert_selector "a[aria-label='Folklore home']"
    assert_no_selector "[data-testid='primary-nav']"
    assert_selector "main", text: "body"
  end

  test "signed in shows the nav with links to every page" do
    render_inline(Layout::ShellComponent.new(current_user: users(:member))) { "body" }

    within_nav = "[data-testid='primary-nav']"
    assert_selector "#{within_nav} [data-testid='nav-workspace'][href='/member']", text: "member"
    assert_selector "#{within_nav} [data-testid='nav-search'][href='/search']"
    assert_selector "#{within_nav} [data-testid='nav-tasks'][href='/tasks']"
    assert_selector "#{within_nav} [data-testid='nav-stale'][href='/stale']"
    assert_selector "#{within_nav} [data-testid='nav-activity'][href='/activity']"
    assert_selector "#{within_nav} [data-testid='nav-settings'][href='/settings/tokens']"
    assert_selector "#{within_nav} form[action='/sign_out'] [data-testid='sign-out']"
  end

  test "offers no editor or upload" do
    render_inline(Layout::ShellComponent.new(current_user: users(:member))) { "body" }

    assert_no_selector "[data-testid='nav-editor']"
    assert_no_selector "[data-testid='nav-upload']"
  end

  test "wide drops the centred column" do
    render_inline(Layout::ShellComponent.new(current_user: users(:member), wide: true)) { "body" }

    assert_no_selector "main.max-w-6xl"
  end
end
