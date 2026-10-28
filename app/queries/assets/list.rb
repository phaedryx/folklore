module Assets
  # Live assets in a directory and everything below it.
  class List
    SORT_COLUMNS = %w[name created_at updated_at].freeze

    def self.query(path:, tags: [], sort: nil, limit: nil, offset: 0, actor: nil)
      scope = Asset.live.under_dir(path.to_s).includes(:tags, :owner).order(:dir, :name)
      scope = scope.tagged_with(tags)
      scope = scope.reorder(sort.to_s) if SORT_COLUMNS.include?(sort.to_s)
      scope = scope.offset(offset.to_i) if offset.to_i.positive?
      scope = scope.limit(limit.to_i) if limit.present?
      scope
    end
  end
end
