module Assets
  # Live assets in a directory and everything below it. No limit returns them
  # all; a limit is capped at MAX_LIMIT. DEFAULT_LIMIT is for callers that page.
  class List
    SORT_COLUMNS = %w[name created_at updated_at].freeze
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500

    def self.query(path:, tags: [], sort: nil, limit: nil, offset: 0, actor: nil)
      scope = Asset.live.under_dir(path.to_s).includes(:tags, :owner).order(:dir, :name)
      scope = scope.tagged_with(tags)
      # The id breaks ties, so offset paging neither skips nor repeats a row.
      scope = scope.reorder(sort.to_s => :asc, id: :asc) if SORT_COLUMNS.include?(sort.to_s)
      scope = scope.offset(offset.to_i) if offset.to_i.positive?
      scope = scope.limit([ limit.to_i, MAX_LIMIT ].min) if limit.present?
      scope
    end
  end
end
