# The asset domain's errors, shared by its queries and mutations so callers
# (MCP tools, the API) map each one once.
module Assets
  Error = Class.new(StandardError)
  NotFoundError = Class.new(Error)
  ForbiddenError = Class.new(Error)
  NameTakenError = Class.new(Error)
  ConflictError = Class.new(Error)
  AlreadyDeletedError = Class.new(Error)
  NotDeletedError = Class.new(Error)
  NotANoteError = Class.new(Error)
  InvalidStatusError = Class.new(Error)
  InvalidLocationError = Class.new(Error)

  # Finds a live asset the actor may write, or raises.
  def self.writable!(slug, actor)
    asset = Asset.live.find_by(slug:)
    raise NotFoundError, slug unless asset
    raise ForbiddenError, "cannot write to #{asset.location}" unless actor.user.can_write_to_workspace?(asset.workspace_handle)

    asset
  end
end
