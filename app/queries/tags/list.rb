module Tags
  # Tags on live assets with a live-asset count each, busiest first.
  class List
    def self.query(within: nil)
      scope = Asset.live
      scope = scope.under_dir(within) if within.present?

      AssetTag.where(asset_id: scope.select(:id))
              .joins(:tag)
              .group("tags.name")
              .count
              .sort_by { |name, count| [ -count, name ] }
    end
  end
end
