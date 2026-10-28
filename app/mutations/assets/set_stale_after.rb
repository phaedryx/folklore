module Assets
  # Schedules (or clears) the date after which an asset should be re-checked,
  # without asserting anything about whether it currently holds. Separate
  # from Verify on purpose: knowing something needs revisiting by a date is
  # a weaker claim than having re-read it.
  class SetStaleAfter
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    InvalidStaleAfterError = Asset::InvalidStaleAfterError

    def self.mutate(actor:, slug:, stale_after:)
      new(actor:, slug:, stale_after:).mutate
    end

    def initialize(actor:, slug:, stale_after:)
      @actor = actor
      @slug = slug
      @stale_after = stale_after
    end

    def mutate
      ActiveRecord::Base.transaction do
        asset = Assets.writable!(@slug, @actor)
        # A review date is not content: updated_at and lock_version stay put,
        # but the row records who scheduled it.
        asset.update_columns(stale_after: Asset.parse_stale_after!(@stale_after),
                             updated_by_token_id: @actor.token&.id, updated_by_agent: @actor.agent)
        Events::Record.mutate(actor: @actor, asset:, action: "asset_review_scheduled",
                              metadata: { "stale_after" => asset.stale_after&.iso8601 })
        asset
      end
    end
  end
end
