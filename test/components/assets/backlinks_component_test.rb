require "test_helper"

class Assets::BacklinksComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "lists each linking asset by name and location, linked to its page" do
    a = create_asset(name: "a.md")
    b = create_asset(path: "member/ideas", name: "b.md")

    render_inline Assets::BacklinksComponent.new(assets: [ a, b ])

    assert_selector "[data-testid='backlinks'] h2", text: "Linked from"
    assert_selector "[data-testid='backlink-#{a.slug}'] a[href='/member/notes/#{a.slug}/a.md']", text: "a.md"
    assert_selector "[data-testid='backlink-#{b.slug}']", text: "member/ideas"
  end

  test "renders nothing when nothing links here" do
    render_inline Assets::BacklinksComponent.new(assets: [])

    assert_no_selector "[data-testid='backlinks']"
  end
end
