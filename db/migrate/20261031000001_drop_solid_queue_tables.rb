# Solid Queue never ran a job: periodic work is rake tasks. Dropped rather than
# the create migration deleted, so databases that already ran it lose the
# tables too and stop dumping them into structure.sql.
class DropSolidQueueTables < ActiveRecord::Migration[8.1]
  TABLES = %w[
    solid_queue_batch_executions solid_queue_batches solid_queue_blocked_executions
    solid_queue_claimed_executions solid_queue_failed_executions solid_queue_jobs
    solid_queue_pauses solid_queue_processes solid_queue_ready_executions
    solid_queue_recurring_executions solid_queue_recurring_tasks
    solid_queue_scheduled_executions solid_queue_semaphores
  ].freeze

  def up
    TABLES.each { |table| drop_table table, if_exists: true, force: :cascade }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
