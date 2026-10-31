# Append-only record of every write, read by the activity tool and page and
# usable as a change cursor by id.
class Event < ApplicationRecord
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :actor_token, class_name: "Token", optional: true
  belongs_to :asset, optional: true

  ACTIONS = %w[
    asset_created asset_updated asset_deleted asset_restored
    tag_added tag_removed
    task_added task_claimed task_completed task_failed task_cancelled task_lease_expired
    version_restored asset_verified asset_review_scheduled asset_status_set
    asset_imported asset_moved
  ].freeze

  validates :action, inclusion: { in: ACTIONS }
end
