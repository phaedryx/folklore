# A claimer and lease exist only while a task is in progress. The original
# constraint tied in_progress to having them, but let a finished task keep a
# claimer as long as its lease was cleared. Who finished a task lives in its
# task_completed / task_failed event, so the row keeps nothing.
class ClearTaskClaimerWhenNotInProgress < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :tasks, name: "tasks_claim_check"
    add_check_constraint :tasks, <<~SQL.squish, name: "tasks_claim_check"
      (status = 'in_progress' AND claimed_by_user_id IS NOT NULL AND claimed_by_agent IS NOT NULL AND lease_until IS NOT NULL)
      OR (status <> 'in_progress' AND claimed_by_user_id IS NULL AND claimed_by_token_id IS NULL
          AND claimed_by_agent IS NULL AND lease_until IS NULL)
    SQL
  end

  def down
    remove_check_constraint :tasks, name: "tasks_claim_check"
    add_check_constraint :tasks,
      "(status = 'in_progress') = (claimed_by_user_id IS NOT NULL AND claimed_by_agent IS NOT NULL AND lease_until IS NOT NULL)",
      name: "tasks_claim_check"
  end
end
