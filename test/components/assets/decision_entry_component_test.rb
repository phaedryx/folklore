require "test_helper"

class Assets::DecisionEntryComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "renders a decision entry with marker and link to asset" do
    asset = create_asset(path: "member/decisions", name: "use-resque.md", content: "", tags: [ "decision" ])

    render_inline Assets::DecisionEntryComponent.new(asset:)

    assert_selector "[data-testid='decision-entry-#{asset.slug}']"
    assert_selector "[data-testid='decision-marker']", text: "decision"
    assert_selector "a", text: "use-resque.md"
  end
end
