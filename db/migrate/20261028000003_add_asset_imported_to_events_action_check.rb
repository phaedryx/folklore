# Importing a bundle records one asset_imported event per asset, so the
# activity feed shows where an asset that nobody created here came from.
class AddAssetImportedToEventsActionCheck < ActiveRecord::Migration[8.1]
  OLD_ACTIONS = %w[
    asset_created asset_updated asset_deleted asset_restored
    tag_added tag_removed
    task_added task_claimed task_completed task_failed task_cancelled task_lease_expired
    version_restored asset_verified asset_review_scheduled asset_status_set
  ].freeze
  NEW_ACTIONS = (OLD_ACTIONS + %w[asset_imported]).freeze

  def up
    replace_check(NEW_ACTIONS)
  end

  def down
    execute "DELETE FROM events WHERE action = 'asset_imported'"
    replace_check(OLD_ACTIONS)
  end

  private

  def replace_check(actions)
    remove_check_constraint :events, name: "events_action_check"
    add_check_constraint :events, "action IN (#{actions.map { |a| "'#{a}'" }.join(', ')})", name: "events_action_check"
  end
end
