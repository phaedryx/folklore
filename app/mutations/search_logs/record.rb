module SearchLogs
  # Writes one row per search: what was asked, with which filters, and what came back.
  # Raw material for growing the eval set past the queries someone thought to write down.
  # Off in the test environment unless FOLKLORE_SEARCH_LOG=1, so the suite's searches do
  # not pile up rows that nothing reads.
  class Record
    def self.enabled?
      !Rails.env.test? || ENV["FOLKLORE_SEARCH_LOG"] == "1"
    end

    def self.mutate(actor:, query:, filters:, result_slugs:)
      new(actor:, query:, filters:, result_slugs:).mutate
    end

    def initialize(actor:, query:, filters:, result_slugs:)
      @actor = actor
      @query = query.to_s
      @filters = filters
      @result_slugs = Array(result_slugs)
    end

    # A filter-only listing (blank query) says nothing about retrieval, so it is skipped.
    def mutate
      return nil unless self.class.enabled? && @query.present?

      SearchLog.create!(query: @query, filters: @filters, result_slugs: @result_slugs, token: @actor.token)
    end
  end
end
