module Assets
  # Brings a tombstoned asset back. The partial unique index refuses it if
  # something live has taken the location meanwhile.
  class Restore
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    NotDeletedError = Assets::NotDeletedError
    NameTakenError = Assets::NameTakenError

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
      raise NotDeletedError, "#{@slug} is not deleted" unless asset.deleted_at?
      raise ForbiddenError, "cannot write to #{asset.location}" unless @actor.user.can_write_to_workspace?(asset.workspace_handle)

      ActiveRecord::Base.transaction do
        asset.lock!(Asset::WRITE_LOCK)
        raise NotDeletedError, "#{@slug} is not deleted" unless asset.deleted_at?

        asset.update!(deleted_at: nil, updated_by_token: @actor.token, updated_by_agent: @actor.agent)
        Links::Sync.mutate(asset:)
        Events::Record.mutate(actor: @actor, asset:, action: "asset_restored")
      end
      asset
    rescue ActiveRecord::RecordNotUnique
      raise NameTakenError, "#{asset.location} is taken by a live asset"
    end
  end
end
