class CreateEvents < ActiveRecord::Migration[8.1]
  ACTIONS = %w[
    asset_created asset_updated asset_deleted asset_restored
    tag_added tag_removed
    task_added task_claimed task_completed task_failed task_cancelled task_lease_expired
    version_restored asset_verified asset_review_scheduled asset_status_set
  ].freeze

  def change
    create_table :events do |t|
      t.references :actor_user, foreign_key: { to_table: :users }, index: false
      t.references :actor_token, foreign_key: { to_table: :tokens }
      t.string :actor_agent
      t.references :asset, foreign_key: true
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false

      t.check_constraint "action IN (#{ACTIONS.map { |a| "'#{a}'" }.join(', ')})", name: "events_action_check"
    end

    add_index :events, :created_at
    add_index :events, %i[actor_user_id created_at]
  end
end
