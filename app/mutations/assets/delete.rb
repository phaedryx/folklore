module Assets
  # Soft-deletes: the row stays for restore and for versions, and the
  # partial unique index frees its name.
  class Delete
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    AlreadyDeletedError = Assets::AlreadyDeletedError

    def self.mutate(actor:, slug:)
      new(actor:, slug:).mutate
    end

    def initialize(actor:, slug:)
      @actor = actor
      @slug = slug
    end

    def mutate
      asset = Asset.find_by(slug: @slug)
      raise NotFoundError, @slug unless asset
      raise AlreadyDeletedError, "#{@slug} is already deleted" if asset.deleted_at?
      raise ForbiddenError, "cannot write to #{asset.location}" unless @actor.user.can_write_to_workspace?(asset.workspace_handle)

      ActiveRecord::Base.transaction do
        asset.lock!
        raise AlreadyDeletedError, "#{@slug} is already deleted" if asset.deleted_at?

        asset.update!(deleted_at: Time.current, updated_by_token: @actor.token, updated_by_agent: @actor.agent)
        Links::Sync.mutate(asset:)
        Events::Record.mutate(actor: @actor, asset:, action: "asset_deleted")
      end
      asset
    end
  end
end
