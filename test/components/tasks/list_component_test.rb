require "test_helper"

class Tasks::ListComponentTest < ViewComponent::TestCase
  include WebTestHelpers

  def add_task(name, path: "member/inbox")
    Tasks::Add.mutate(actor: web_actor, path:, name:, content: "")
  end

  test "one row per task with its link, location and status" do
    first = add_task("first.md")
    second = add_task("second.md", path: "member/stories/sc-1")

    render_inline Tasks::ListComponent.new(tasks: [ first, second ])

    assert_selector "[data-testid='task-row-#{first.slug}'] a[href='/member/inbox/#{first.slug}/first.md']", text: "first.md"
    assert_selector "[data-testid='task-row-#{second.slug}']", text: "member/stories/sc-1"
    assert_selector "[data-testid='task-status-pill']", count: 2
  end

  test "a claimed task shows its claimer as handle/agent and when the lease runs out" do
    task = add_task("claimed.md")
    travel_to Time.utc(2026, 10, 28, 12, 0) do
      Tasks::Claim.mutate(actor: web_actor, slug: task.slug, lease_seconds: 3600)

      render_inline Tasks::ListComponent.new(tasks: [ task.reload ])
    end

    assert_selector "[data-testid='task-claimer']", text: "member/web"
    assert_selector "[data-testid='task-lease'] time[datetime='2026-10-28T13:00:00Z']", text: "2026-10-28 13:00 UTC"
    assert_selector "[data-testid='task-lease']", text: "lease until"
  end

  test "an expired lease says so" do
    task = add_task("stale-claim.md")
    Tasks::Claim.mutate(actor: web_actor, slug: task.slug, lease_seconds: 60)

    travel 2.minutes do
      render_inline Tasks::ListComponent.new(tasks: [ task.reload ])
    end

    assert_selector "[data-testid='task-lease']", text: "lease expired"
  end

  test "an unclaimed task shows no claimer or lease" do
    render_inline Tasks::ListComponent.new(tasks: [ add_task("open.md") ])

    assert_no_selector "[data-testid='task-claimer']"
    assert_no_selector "[data-testid='task-lease']"
  end
end
