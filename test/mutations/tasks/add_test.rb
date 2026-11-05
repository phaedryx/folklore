require "test_helper"

class Tasks::AddTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def add(name, path: "member/inbox", content: "", **args)
    Tasks::Add.mutate(**{ actor: @actor, path:, name:, content: }.merge(args))
  end

  test "creates a live asset with a pending task row and no claimer" do
    asset = add("step.md", path: "member/stories/sc-1", content: "do the thing")

    assert asset.task?
    assert_equal "pending", asset.task.status
    assert_nil asset.task.claimed_by_user_id
    assert_nil asset.task.claimed_by_agent
    assert_nil asset.task.lease_until
    assert_equal 0, asset.task.attempts
    assert_equal @actor.user.id, asset.owner_id
    assert_equal "do the thing", asset.content
    assert_nil asset.status
  end

  test "passes caller-supplied tags through verbatim without injecting a 'task' tag" do
    asset = add("tagged.md", tags: [ "urgent" ])

    assert_equal [ "urgent" ], asset.tags.pluck(:name)
  end

  test "a task with no tags is still a task: the facet row is the identity" do
    asset = add("untagged.md")

    assert_empty asset.tags
    assert asset.task?
  end

  test "writes one task_added event and no asset_created event" do
    asset = add("todo.md")

    events = Event.where(asset_id: asset.id)
    assert_equal [ "task_added" ], events.pluck(:action)
    assert_equal @actor.user.id, events.first.actor_user_id
    assert_equal "default", events.first.actor_agent
  end

  test "writes the asset, the task row and the event in one transaction" do
    # Shadow the inherited create! on Task alone; removing the singleton
    # method afterwards restores the inherited one.
    Task.define_singleton_method(:create!) { |**| raise ActiveRecord::StatementInvalid, "boom" }
    begin
      assert_raises(ActiveRecord::StatementInvalid) { add("atomic.md") }
    ensure
      Task.singleton_class.send(:remove_method, :create!)
    end

    assert_equal 0, Asset.where(dir: "member/inbox", name: "atomic.md").count
    assert_equal 0, Task.count
  end

  test "accepts any path layout under the caller's workspace" do
    [ "member/stories/proj-123/tasks/a.md", "member/projects/foo/b.md", "member/inbox/c.md" ].each do |full|
      path, _, name = full.rpartition("/")
      assert add(name, path:).task?, "expected #{full} to be a task"
    end
  end

  test "rejects a path under another member's workspace" do
    assert_raises(Tasks::Add::ForbiddenError) { add("x.md", path: "other/stories") }
  end

  test "rejects a reserved directory" do
    assert_raises(Tasks::Add::ReservedDirError) { add("x.md", path: "member/archive") }
    assert_raises(Tasks::Add::ReservedDirError) { add("x.md", path: "member/state") }
  end

  test "rejects a duplicate name at the same path" do
    add("dup.md")

    assert_raises(Tasks::Add::NameTakenError) { add("dup.md") }
  end

  # Dependencies: set once, at creation, by slug.

  test "depends_on records each dependency and the slugs in the task_added event" do
    first = add("first.md")
    second = add("second.md")

    dependent = add("third.md", depends_on: [ first.slug, second.slug, first.slug ])

    assert_equal [ first.id, second.id ].sort, dependent.task.dependencies.map(&:asset_id).sort
    assert_equal [ first.slug, second.slug ], Event.where(asset_id: dependent.id, action: "task_added").sole.metadata["depends_on"]
  end

  test "a task with no dependencies records none in its event" do
    asset = add("alone.md")

    assert_nil Event.where(asset_id: asset.id, action: "task_added").sole.metadata["depends_on"]
    assert_empty asset.task.dependencies
  end

  test "a dependency may be a task in another member's workspace, or one already done" do
    theirs = Tasks::Add.mutate(actor: actor_for(:other_default), path: "other/inbox", name: "theirs.md", content: "")
    done = add("done.md")
    Tasks::Claim.mutate(actor: @actor, slug: done.slug)
    Tasks::Complete.mutate(actor: @actor, slug: done.slug)

    dependent = add("mine.md", depends_on: [ theirs.slug, done.slug ])

    assert_equal [ theirs.id, done.id ].sort, dependent.task.dependencies.map(&:asset_id).sort
  end

  test "refuses depends_on naming a note, and creates nothing" do
    note = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "n.md", content: "")

    error = assert_raises(Tasks::NotATaskError) { add("blocked.md", depends_on: [ note.slug ]) }

    assert_equal note.slug, error.message
    assert_equal 0, Asset.where(dir: "member/inbox", name: "blocked.md").count
    assert_equal 0, TaskDependency.count
  end

  test "refuses depends_on naming an unknown or deleted slug, and creates nothing" do
    gone = add("gone.md")
    Assets::Delete.mutate(actor: @actor, slug: gone.slug)

    assert_equal "00000000", assert_raises(Assets::NotFoundError) { add("x.md", depends_on: [ "00000000" ]) }.message
    assert_equal gone.slug, assert_raises(Assets::NotFoundError) { add("x.md", depends_on: [ gone.slug ]) }.message
    assert_equal 0, Asset.where(dir: "member/inbox", name: "x.md").count
    assert_equal 0, TaskDependency.count
  end
end
