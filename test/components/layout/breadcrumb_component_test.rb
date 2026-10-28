require "test_helper"

class Layout::BreadcrumbComponentTest < ViewComponent::TestCase
  test "renders nothing when location is blank" do
    render_inline Layout::BreadcrumbComponent.new(handle: "alice", location: nil)

    assert_no_selector "nav"
  end

  test "renders nothing when location is empty string" do
    render_inline Layout::BreadcrumbComponent.new(handle: "alice", location: "")

    assert_no_selector "nav"
  end

  test "renders handle as root crumb" do
    render_inline Layout::BreadcrumbComponent.new(handle: "alice", location: "notes")

    assert_selector "nav[aria-label='breadcrumb'] ol li", text: "alice"
  end

  test "renders all segments for a nested location" do
    render_inline Layout::BreadcrumbComponent.new(handle: "alice", location: "stories/proj-123")

    assert_selector "nav ol li", text: "stories"
    assert_selector "nav ol li", text: "proj-123"
  end

  test "links handle to workspace root" do
    render_inline Layout::BreadcrumbComponent.new(handle: "alice", location: "notes")

    assert_selector "nav ol li a[href='/alice']", text: "alice"
  end

  test "links segments to their workspace paths" do
    render_inline Layout::BreadcrumbComponent.new(handle: "alice", location: "stories/proj-123")

    assert_selector "nav ol li a[href='/alice/stories']", text: "stories"
    assert_selector "nav ol li a[href='/alice/stories/proj-123']", text: "proj-123"
  end
end
