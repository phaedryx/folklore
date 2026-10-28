module SearchLogs
  # Marks a search as answered: the same token read one of its results soon after. The
  # `read` tool calls this on every read; a read that no recent search returned is a no-op.
  class Follow
    WINDOW = 5.minutes

    def self.mutate(actor:, slug:)
      new(actor:, slug:).mutate
    end

    def initialize(actor:, slug:)
      @actor = actor
      @slug = slug.to_s
    end

    # Only the latest unanswered match is marked: one read answers one search, and a log
    # already followed keeps its first answer.
    def mutate
      return nil unless Record.enabled? && @actor.token

      log = SearchLog.where(token: @actor.token, followed_slug: nil)
                     .where(created_at: WINDOW.ago..)
                     .where("? = ANY (result_slugs)", @slug)
                     .order(created_at: :desc, id: :desc)
                     .first
      return nil unless log

      log.update!(followed_slug: @slug)
      log
    end
  end
end
