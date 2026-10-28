require "test_helper"

class Layout::HeaderComponentTest < ViewComponent::TestCase
  test "renders the owner handle" do
    render_inline Layout::HeaderComponent.new(owner: users(:member))

    assert_selector "[data-testid='workspace-handle']", text: "member"
  end

  test "renders no breadcrumb when location is absent" do
    render_inline Layout::HeaderComponent.new(owner: users(:member))

    assert_no_selector "nav[aria-label='breadcrumb']"
  end

  test "renders breadcrumb when location is present" do
    render_inline Layout::HeaderComponent.new(owner: users(:member), location: "notes")

    assert_selector "nav[aria-label='breadcrumb']"
    assert_selector "nav ol li", text: "notes"
  end
end
