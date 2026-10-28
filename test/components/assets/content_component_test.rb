require "test_helper"

class Assets::ContentComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "renders markdown in a prose article" do
    render_inline Assets::ContentComponent.new(asset: create_asset(name: "a.md", content: "# Hi"))

    assert_selector "article[data-testid='asset-content'][data-render='markdown'].prose-asset h1", text: "Hi"
  end

  test "renders code highlighted" do
    render_inline Assets::ContentComponent.new(asset: create_asset(name: "a.rb", content: "puts 1"))

    assert_selector "[data-testid='asset-content'][data-render='code'].highlight pre code span.nb", text: "puts"
  end

  test "renders unknown types as plain text" do
    render_inline Assets::ContentComponent.new(asset: create_asset(name: "a.zzz", content: "<b>x</b>"))

    assert_selector "pre[data-testid='asset-content'][data-render='plain']", text: "<b>x</b>"
  end

  test "rewrites wikilinks to the target's show page" do
    target = create_asset(name: "target.md", content: "x")

    render_inline Assets::ContentComponent.new(asset: create_asset(name: "src.md", content: "[[#{target.slug}]]"))

    assert_selector "a[href='/member/notes/#{target.slug}/target.md']", text: "target.md"
  end

  test "renders nothing for empty content" do
    render_inline Assets::ContentComponent.new(asset: create_asset(name: "empty.md", content: ""))

    assert_no_selector "[data-testid='asset-content']"
  end
end
