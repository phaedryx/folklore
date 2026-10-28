require "test_helper"

class Tasks::StatusPillComponentTest < ViewComponent::TestCase
  test "pending carries its status and label" do
    render_inline Tasks::StatusPillComponent.new(status: "pending")

    assert_selector "[data-testid='task-status-pill'][data-status='pending']", text: "pending"
  end

  test "in_progress reads as words" do
    render_inline Tasks::StatusPillComponent.new(status: "in_progress")

    assert_selector "[data-testid='task-status-pill']", text: "in progress"
  end

  test "every status has its own styling" do
    classes = Task::STATUSES.map do |status|
      render_inline(Tasks::StatusPillComponent.new(status:)).at_css("[data-testid='task-status-pill']")["class"]
    end

    assert_equal Task::STATUSES.size, classes.uniq.size
  end
end
