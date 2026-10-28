module Assets
  # Re-confirms that an asset still holds, and optionally sets the date after
  # which it should be re-confirmed again.
  #
  # Verification is not an edit: updated_at and updated_by stay as they were,
  # so "recently changed" remains a content signal, and no version is cut.
  class Verify
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    InvalidStaleAfterError = Asset::InvalidStaleAfterError

    # Distinguishes "caller said nothing about stale_after" from "caller asked
    # to clear it", which arrives as an empty string.
    UNCHANGED = Object.new.freeze

    def self.mutate(actor:, slug:, stale_after: UNCHANGED)
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
        asset.lock!
        changes = { verified_at: Time.current, verified_by_token_id: @actor.token&.id, verified_by_agent: @actor.agent }
        changes[:stale_after] = Asset.parse_stale_after!(@stale_after) unless @stale_after.equal?(UNCHANGED)
        # Not an edit: neither updated_at nor lock_version moves, so a caller
        # holding the version from before the verify can still update.
        asset.update_columns(changes)
        Events::Record.mutate(actor: @actor, asset:, action: "asset_verified",
                              metadata: { "stale_after" => asset.stale_after&.iso8601 })
        asset
      end
    end
  end
end
