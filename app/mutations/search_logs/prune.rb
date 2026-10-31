module SearchLogs
  # Deletes search logs older than the retention window. Nothing reads old logs back except
  # the person mining them for eval queries, so they are kept long enough for that and no
  # longer. Run by hand or from cron with `bin/rails folklore:prune_search_logs`.
  class Prune
    DEFAULT_RETENTION = 180.days

    def self.mutate(older_than: DEFAULT_RETENTION)
      new(older_than:).mutate
    end

    def initialize(older_than:)
      raise ArgumentError, "older_than must be positive, got #{older_than.inspect}" unless older_than.positive?

      @older_than = older_than
    end

    # Returns how many rows were deleted.
    def mutate
      SearchLog.where(created_at: ...@older_than.ago).delete_all
    end
  end
end
