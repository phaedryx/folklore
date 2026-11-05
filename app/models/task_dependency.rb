# One edge of the task graph: `task` cannot be claimed until `depends_on` is
# done. Both ends are tasks (the foreign keys point at the tasks table), a
# task cannot depend on itself, and the pair is the key. Edges are written
# only by Tasks::Add, so the graph is acyclic by construction.
class TaskDependency < ApplicationRecord
  self.primary_key = %i[task_asset_id depends_on_asset_id]

  belongs_to :task, foreign_key: :task_asset_id, inverse_of: :task_dependencies
  belongs_to :depends_on, class_name: "Task", foreign_key: :depends_on_asset_id
end
