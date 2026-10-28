# The task facet of an asset: its presence makes the asset a task. Claims are
# leased and recorded against (user, agent), so two agents on one token
# exclude each other.
class Task < ApplicationRecord
  self.primary_key = "asset_id"

  belongs_to :asset
  belongs_to :claimed_by_token, class_name: "Token", optional: true
  belongs_to :claimed_by_user, class_name: "User", optional: true

  STATUSES = %w[pending in_progress done failed cancelled].freeze

  validates :status, inclusion: { in: STATUSES }

  def lease_expired?
    lease_until.present? && lease_until < Time.current
  end
end
