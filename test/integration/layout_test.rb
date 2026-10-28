require "test_helper"

class LayoutTest < ActionDispatch::IntegrationTest
  test "a signed-in page renders inside the shell with the primary nav" do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }

    get root_path

    assert_select "title", "Folklore"
    assert_select "a[aria-label='Folklore home']"
    assert_select "[data-testid='primary-nav'] [data-testid='nav-workspace']", text: /member/
  end

  test "the sign-in page renders inside the shell without the nav" do
    get sign_in_path

    assert_select "a[aria-label='Folklore home']"
    assert_select "[data-testid='primary-nav']", false
  end

  test "the palette, rouge theme and clipboard script are linked" do
    get sign_in_path

    assert_select "link[rel=stylesheet][href*='tailwind']"
    assert_select "link[rel=stylesheet][href*='rouge']"
    assert_match %r{"clipboard":}, response.body
  end
end
