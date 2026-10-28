module Tags
  Error = Class.new(StandardError)
  NotFoundError = Class.new(Error)
  ForbiddenError = Class.new(Error)
  AlreadyAppliedError = Class.new(Error)
  NotAppliedError = Class.new(Error)
  InvalidTagError = Class.new(Error)

  # Finds a live asset the actor may tag and row-locks it, or raises; the
  # same checks as Assets.writable!, with this domain's errors.
  def self.writable!(slug, actor)
    ::Assets.writable!(slug, actor)
  rescue ::Assets::NotFoundError
    raise NotFoundError, slug
  rescue ::Assets::ForbiddenError => e
    raise ForbiddenError, e.message
  end

  # A tag change is an edit, as it is through Assets::Update: it stamps the
  # editor, moves updated_at, bumps lock_version (so an expected_version taken
  # before it conflicts) and records asset_updated beside the tag event.
  def self.touch!(asset, actor)
    asset.update!(updated_by_token: actor.token, updated_by_agent: actor.agent, updated_at: Time.current)
    Events::Record.mutate(actor:, asset:, action: "asset_updated")
    asset
  end
end
