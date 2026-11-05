require "application_system_test_case"

class TasksPageSystemTest < ApplicationSystemTestCase
  setup do
    @member = users(:member)
    sign_in(@member, password: "member-secret")
  end

  test "the nav reaches the tasks page, and a status filter narrows it" do
    Tasks::Add.mutate(actor: web_actor, path: "member/inbox", name: "open.md", content: "")
    claimed = Tasks::Add.mutate(actor: web_actor, path: "member/inbox", name: "busy.md", content: "")
    Tasks::Claim.mutate(actor: web_actor, slug: claimed.slug)

    visit root_path
    within("[data-testid='primary-nav']") { click_on "Tasks" }
    assert_selector "[data-testid='tasks-list']", text: "open.md"
    assert_text "busy.md"

    click_on "in progress"
    assert_selector "[data-testid='task-row-#{claimed.slug}'] [data-testid='task-claimer']", text: "member/web"
    assert_no_text "open.md"

    click_on "busy.md"
    assert_title "busy.md · Folklore"
  end

  test "a task lists what it depends on, and is marked blocked until that is done" do
    dep = Tasks::Add.mutate(actor: web_actor, path: "member/inbox", name: "first.md", content: "")
    dependent = Tasks::Add.mutate(actor: web_actor, path: "member/inbox", name: "second.md", content: "", depends_on: [ dep.slug ])

    visit tasks_path
    within("[data-testid='task-row-#{dependent.slug}']") do
      assert_selector "[data-testid='task-blocked']", text: "blocked"
      assert_link "first.md", href: %r{/member/inbox/#{dep.slug}/first\.md}
    end
    assert_no_selector "[data-testid='task-row-#{dep.slug}'] [data-testid='task-blocked']"

    Tasks::Claim.mutate(actor: web_actor, slug: dep.slug)
    Tasks::Complete.mutate(actor: web_actor, slug: dep.slug)
    visit tasks_path
    within("[data-testid='task-row-#{dependent.slug}']") do
      assert_no_selector "[data-testid='task-blocked']"
      assert_link "first.md"
    end
  end
end
