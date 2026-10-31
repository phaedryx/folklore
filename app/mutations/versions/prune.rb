module Versions
  # Deletes all but each asset's `keep` newest versions, newest by created_at
  # as the History page orders them (an import can load old versions with new
  # ids). Run by Checkpoints::Write on the checkpoint it just wrote, and over
  # every asset by `bin/rails folklore:prune_versions`. Returns the number of
  # versions deleted.
  class Prune
    InvalidKeepError = Versions::InvalidKeepError

    def self.mutate(keep:, assets: Asset.all)
      new(keep:, assets:).mutate
    end

    def initialize(keep:, assets:)
      @keep = Integer(keep.to_s, 10, exception: false)
      raise InvalidKeepError, "keep must be a whole number, 0 or more, got #{keep.inspect}" if @keep.nil? || @keep.negative?

      @assets = assets
    end

    def mutate
      ranked = Version.where(asset_id: @assets.select(:id))
                      .select("id, row_number() OVER (PARTITION BY asset_id ORDER BY created_at DESC, id DESC) AS rank")
      Version.where(id: Version.from(ranked, :versions).where("rank > ?", @keep).select(:id)).delete_all
    end
  end
end
