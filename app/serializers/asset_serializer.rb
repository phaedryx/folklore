class AssetSerializer
  def self.call(asset)
    {
      slug: asset.slug,
      name: asset.name,
      content: asset.content,
      content_type: asset.content_type,
      status: asset.status,
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
      created_by: actor(asset.created_by_token),
      updated_by: actor(asset.updated_by_token),
      verified_by: actor(asset.verified_by_token),
      task: task(asset.task)
    }
  end

  def self.actor(token)
    return nil unless token

    { handle: token.user.handle, agent: token.agent_name }
  end

  def self.task(task)
    return nil unless task

    claimed_by = "#{task.claimed_by_user.handle}/#{task.claimed_by_agent}" if task.claimed_by_user
    { status: task.status, claimed_by:, lease_until: task.lease_until&.iso8601 }
  end
end
