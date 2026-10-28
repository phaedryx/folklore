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

  # Tenancy lives here, not in the queries: every member reads everything,
  # so the read queries accept `actor:` without narrowing by it (see
  # test/queries/read_authorization_test.rb), and writes are owner-only,
  # checked by the mutations through this method and the owner checks in
  # Create, Delete and Restore.
  #
  # Finds a live asset the actor may write and row-locks it, or raises. Call
  # it inside the mutation's transaction. Liveness is checked again under the
  # lock, so a delete that committed while this waited is not written through.
  def self.writable!(slug, actor)
    asset = Asset.live.find_by(slug:)
    raise NotFoundError, slug unless asset
    raise ForbiddenError, "cannot write to #{asset.location}" unless actor.user.can_write_to_workspace?(asset.workspace_handle)

    asset.lock!(Asset::WRITE_LOCK)
    raise NotFoundError, slug if asset.deleted_at?

    asset
  end
end
