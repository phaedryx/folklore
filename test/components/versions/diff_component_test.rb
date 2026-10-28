require "test_helper"

class Versions::DiffComponentTest < ViewComponent::TestCase
  test "renders unchanged lines in both columns" do
    render_inline Versions::DiffComponent.new(old_content: "alpha\nbeta", new_content: "alpha\nbeta")

    assert_selector "[data-testid='version-diff']"
    assert_selector "[data-diff-side='old'] .diff-line", text: "alpha"
    assert_selector "[data-diff-side='new'] .diff-line", text: "beta"
  end

  test "marks a changed line as removed on the old side and added on the new side" do
    render_inline Versions::DiffComponent.new(old_content: "one\nbeta", new_content: "one\ngamma")

    assert_selector "[data-diff-side='old'] .diff-removed", text: "beta"
    assert_selector "[data-diff-side='new'] .diff-added", text: "gamma"
  end

  test "marks an inserted line as added only on the new side" do
    render_inline Versions::DiffComponent.new(old_content: "one", new_content: "one\ntwo")

    assert_selector "[data-diff-side='new'] .diff-added", text: "two"
    assert_selector "[data-diff-side='old'] .diff-empty", count: 1
  end

  test "escapes markup in content" do
    render_inline Versions::DiffComponent.new(old_content: "<b>x</b>", new_content: "")

    assert_selector "[data-diff-side='old'] .diff-removed", text: "<b>x</b>"
  end
end
