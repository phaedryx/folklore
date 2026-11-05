# A task's dependencies: the tasks that must be done before it can be claimed.
# Both ends are tasks (the foreign keys point at tasks, not assets), a task
# cannot depend on itself, and the pair is the key. Dependencies are set only
# when a task is added, so the graph is acyclic by construction (see
# Tasks::Add) and the table needs no cycle check.
class CreateTaskDependencies < ActiveRecord::Migration[8.1]
  def change
    create_table :task_dependencies, primary_key: %i[task_asset_id depends_on_asset_id] do |t|
      t.bigint :task_asset_id, null: false
      t.bigint :depends_on_asset_id, null: false
      t.timestamptz :created_at, null: false

      t.check_constraint "task_asset_id <> depends_on_asset_id", name: "task_dependencies_distinct_check"
    end

    add_foreign_key :task_dependencies, :tasks, column: :task_asset_id, primary_key: :asset_id, on_delete: :cascade
    add_foreign_key :task_dependencies, :tasks, column: :depends_on_asset_id, primary_key: :asset_id, on_delete: :cascade
    add_index :task_dependencies, :depends_on_asset_id
  end
end
