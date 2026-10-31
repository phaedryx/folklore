module Tasks
  # Drops the claim on a task whose asset is being deleted, putting it back to
  # pending, so a restored task does not come back still held. Runs inside the
  # caller's transaction. Returns the released claimer's label, or nil when the
  # asset is not a held task.
  class Release
    def self.mutate(asset:)
      task = Task.lock.find_by(asset_id: asset.id)
      return unless task&.status == "in_progress"

      released = Tasks.label(task.claimed_by_user_id, task.claimed_by_agent)
      task.update!(status: "pending", claimed_by_user: nil, claimed_by_token: nil, claimed_by_agent: nil, lease_until: nil)
      released
    end
  end
end
