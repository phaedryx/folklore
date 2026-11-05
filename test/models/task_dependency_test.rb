require "test_helper"

# The invariants live in the database: both ends are tasks, a task cannot
# depend on itself, and a pair is recorded once.
class TaskDependencyTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def add(name)
    Tasks::Add.mutate(actor: @actor, path: "member/inbox", name:, content: "")
  end

  def insert(task_asset_id, depends_on_asset_id)
    TaskDependency.insert!({ task_asset_id:, depends_on_asset_id:, created_at: Time.current })
  end

  test "the database refuses a task depending on itself" do
    task = add("self.md")

    assert_raises(ActiveRecord::StatementInvalid) { insert(task.id, task.id) }
  end

  test "the database refuses depending on an asset that is not a task" do
    note = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "n.md", content: "")

    assert_raises(ActiveRecord::InvalidForeignKey) { insert(add("task.md").id, note.id) }
  end

  test "the database refuses a dependent that is not a task" do
    note = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "n.md", content: "")

    assert_raises(ActiveRecord::InvalidForeignKey) { insert(note.id, add("task.md").id) }
  end

  test "the same pair is recorded once" do
    task = add("task.md")
    dep = add("dep.md")
    insert(task.id, dep.id)

    assert_raises(ActiveRecord::RecordNotUnique) { insert(task.id, dep.id) }
  end
end
