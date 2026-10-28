require "test_helper"

class TasksPageTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  def add_task(name, path: "member/inbox", fixture: :member, tags: [])
    Tasks::Add.mutate(actor: web_actor(fixture), path:, name:, content: "", tags:)
  end

  test "empty state when the workspace has no tasks" do
    create_asset(name: "note.md")

    get tasks_path
    assert_response :success
    assert_select "[data-testid='tasks-empty']"
  end

  test "lists every status in the caller's workspace, oldest first" do
    add_task("pending.md")
    claimed = add_task("claimed.md", path: "member/stories/sc-1")
    Tasks::Claim.mutate(actor: web_actor, slug: claimed.slug)
    done = add_task("done.md")
    Tasks::Claim.mutate(actor: web_actor, slug: done.slug)
    Tasks::Complete.mutate(actor: web_actor, slug: done.slug)

    get tasks_path
    assert_select "[data-testid='tasks-list'] [data-testid^='task-row-']", count: 3
    assert_operator response.body.index("pending.md"), :<, response.body.index("done.md")
    assert_select "[data-testid='task-row-#{claimed.slug}'] [data-testid='task-claimer']", text: "member/web"
    assert_select "[data-testid='task-row-#{claimed.slug}']", text: %r{member/stories/sc-1}
  end

  test "another user's tasks are not listed" do
    add_task("theirs.md", path: "other/inbox", fixture: :other)

    get tasks_path
    assert_select "[data-testid='tasks-empty']"
  end

  test "filters by status" do
    add_task("open.md")
    claimed = add_task("busy.md")
    Tasks::Claim.mutate(actor: web_actor, slug: claimed.slug)

    get tasks_path(status: "in_progress")
    assert_no_match(/open\.md/, response.body)
    assert_match "busy.md", response.body
    assert_select "[data-testid='tasks-filter-in_progress'][aria-current='page']"
  end

  test "filters by tags" do
    add_task("tagged.md", tags: %w[ops])
    add_task("plain.md")

    get tasks_path(tags: "ops")
    assert_match "tagged.md", response.body
    assert_no_match(/plain\.md/, response.body)
  end

  test "an unknown status redirects back with an alert" do
    get tasks_path(status: "bogus")
    assert_redirected_to tasks_path
    follow_redirect!
    assert_select "[data-testid='flash-alert']", text: /status must be one of/
  end

  test "requires sign in" do
    delete sign_out_path
    get tasks_path
    assert_redirected_to sign_in_path
  end
end
