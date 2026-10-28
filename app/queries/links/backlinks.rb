module Links
  # Live assets whose wikilinks resolve to the given asset.
  class Backlinks
    def self.query(asset:)
      new(asset:).query
    end

    def initialize(asset:)
      @asset = asset
    end

    def query
      Asset.live
           .joins(:links)
           .where(links: { dst_asset_id: @asset.id, kind: "wikilink" })
           .distinct
           .order(:dir, :name)
    end
  end
end
