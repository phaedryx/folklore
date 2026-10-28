class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks, id: false, primary_key: :asset_id do |t|
      t.references :asset, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "pending"
      t.references :claimed_by_token, foreign_key: { to_table: :tokens }
      t.references :claimed_by_user, foreign_key: { to_table: :users }
      t.string :claimed_by_agent
      t.timestamptz :lease_until
      t.integer :attempts, null: false, default: 0
      t.text :outcome_note
      t.timestamps

      t.check_constraint "status IN ('pending', 'in_progress', 'done', 'failed', 'cancelled')", name: "tasks_status_check"
      t.check_constraint "(status = 'in_progress') = (claimed_by_user_id IS NOT NULL AND claimed_by_agent IS NOT NULL AND lease_until IS NOT NULL)", name: "tasks_claim_check"
    end

    execute "ALTER TABLE tasks ADD PRIMARY KEY (asset_id)"
    add_index :tasks, %i[status lease_until]
  end
end
