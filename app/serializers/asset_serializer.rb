class AssetSerializer
  # Every association `call` reads. Preload these before serializing a list.
  PRELOADS = [
    :owner, :tags,
    { created_by_token: :user, updated_by_token: :user, verified_by_token: :user, task: :claimed_by_user }
  ].freeze

  def self.preload(assets)
    ActiveRecord::Associations::Preloader.new(records: Array(assets), associations: PRELOADS).call
    assets
  end

  def self.call(asset)
    {
      slug: asset.slug,
      name: asset.name,
      content: asset.content,
      content_type: asset.content_type,
      status: status(asset),
      owner_handle: asset.owner.handle,
      path: asset.dir,
      dir: asset.dir,
      location: asset.location,
      tags: asset.tags.map(&:name),
      created_at: asset.created_at.iso8601,
      updated_at: asset.updated_at.iso8601,
      version: asset.lock_version,
      stale_after: asset.stale_after&.iso8601,
      verified_at: asset.verified_at&.iso8601,
      created_by: actor(asset, asset.created_by_token, asset.created_by_agent),
      updated_by: actor(asset, asset.updated_by_token, asset.updated_by_agent),
      verified_by: actor(asset, asset.verified_by_token, asset.verified_by_agent),
      task: task(asset.task)
    }
  end

  # One `status` field for callers that predate the tasks facet: a task's
  # lifecycle state, otherwise the note status. `task` keeps the detail.
  def self.status(asset)
    asset.task ? asset.task.status : asset.status
  end

  # Writes are owner-only, so a web write (no token) is the owner acting as "web".
  def self.actor(asset, token, agent)
    return nil if agent.nil?

    { handle: (token&.user || asset.owner).handle, agent: }
  end

  def self.task(task)
    return nil unless task

    claimed_by = "#{task.claimed_by_user.handle}/#{task.claimed_by_agent}" if task.claimed_by_user
    { status: task.status, claimed_by:, lease_until: task.lease_until&.iso8601 }
  end
end
