require "test_helper"

class Tags::ChipComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "renders the tag name" do
    render_inline Tags::ChipComponent.new(name: "shell")

    assert_selector "[data-testid='tag-chip']", text: "shell"
  end

  test "renders different tag names" do
    render_inline Tags::ChipComponent.new(name: "onboarding")

    assert_selector "[data-testid='tag-chip']", text: "onboarding"
  end
end
