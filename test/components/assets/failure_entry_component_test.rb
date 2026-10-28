require "test_helper"

class Assets::FailureEntryComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "renders a failure entry with marker and link to asset" do
    asset = create_asset(path: "member/failures", name: "saml-loop.md", content: "", tags: [ "failure" ])

    render_inline Assets::FailureEntryComponent.new(asset:)

    assert_selector "[data-testid='failure-entry-#{asset.slug}']"
    assert_selector "[data-testid='failure-marker']", text: "failure"
    assert_selector "a", text: "saml-loop.md"
  end
end
