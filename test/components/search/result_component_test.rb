require "test_helper"

class Search::ResultComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "renders asset name with link and its folder" do
    asset = create_asset(name: "result.md", content: "some content")

    render_inline Search::ResultComponent.new(asset:)

    assert_selector "[data-testid='search-result-#{asset.slug}']"
    assert_selector "a[href='/member/notes/#{asset.slug}/result.md']", text: "result.md"
    assert_text "member/notes"
  end

  test "renders tag chips" do
    asset = create_asset(name: "tagged.md", content: "", tags: %w[shell])

    render_inline Search::ResultComponent.new(asset:)

    assert_selector "[data-testid='tag-chip']", text: "shell"
  end

  test "renders without tags when asset has none" do
    asset = create_asset(name: "plain.md", content: "")

    render_inline Search::ResultComponent.new(asset:)

    assert_no_selector "[data-testid='tag-chip']"
  end
end
