require "test_helper"

class Assets::CardComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  test "renders asset name with link" do
    asset = create_asset(name: "hello.md", content: "# Hello")

    render_inline Assets::CardComponent.new(asset:)

    assert_selector "[data-testid='asset-#{asset.slug}']"
    assert_selector "a[href='/member/notes/#{asset.slug}/hello.md']", text: "hello.md"
  end

  test "renders content type" do
    asset = create_asset(path: "member/scripts", name: "deploy.sh", content: "#!/bin/bash")

    render_inline Assets::CardComponent.new(asset:)

    assert_text "application/x-sh"
  end

  test "renders tags as chips" do
    asset = create_asset(name: "tagged.md", content: "", tags: %w[shell docs])

    render_inline Assets::CardComponent.new(asset:)

    assert_selector "[data-testid='tag-chip']", text: "shell"
    assert_selector "[data-testid='tag-chip']", text: "docs"
  end

  test "renders without tags when asset has none" do
    asset = create_asset(name: "plain.md", content: "")

    render_inline Assets::CardComponent.new(asset:)

    assert_no_selector "[data-testid='tag-chip']"
  end
end
