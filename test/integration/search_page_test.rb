require "test_helper"

class SearchPageTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  test "no query shows the form and no results" do
    get search_path
    assert_response :success
    assert_select "[data-testid='search-form']"
    assert_select "[data-testid='search-results']", false
    assert_select "[data-testid='search-empty']", false
  end

  test "finds assets by content across workspaces" do
    mine = create_asset(name: "jokes.sh", content: "echo something distinctive")
    theirs = create_asset(path: "other/notes", name: "t.md", content: "also distinctive", fixture: :other)

    get search_path(q: "distinctive")
    assert_select "[data-testid='search-result-#{mine.slug}']"
    assert_select "[data-testid='search-result-#{theirs.slug}']"
    assert_select "input[name=q][value=distinctive]"
  end

  test "narrows by tags" do
    tagged = create_asset(name: "a.md", content: "kettle", tags: %w[kitchen])
    plain = create_asset(name: "b.md", content: "kettle")

    get search_path(q: "kettle", tags: "kitchen")
    assert_select "[data-testid='search-result-#{tagged.slug}']"
    assert_select "[data-testid='search-result-#{plain.slug}']", false
  end

  test "tags alone are a search" do
    tagged = create_asset(name: "a.md", content: "x", tags: %w[kitchen])

    get search_path(tags: "kitchen")
    assert_select "[data-testid='search-result-#{tagged.slug}']"
  end

  test "no matches says so" do
    get search_path(q: "nothingmatchesthis")
    assert_select "[data-testid='search-empty']", text: /nothingmatchesthis/
  end
end
