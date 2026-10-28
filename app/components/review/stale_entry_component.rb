module Review
  # One overdue asset in the review queue, with a verify form whose next
  # review date is pre-filled rather than applied: verifying should not
  # silently reschedule.
  class StaleEntryComponent < ViewComponent::Base
    DEFAULT_INTERVAL = 90.days

    def initialize(asset:)
      @asset = asset
    end

    def overdue_label
      days = (Date.current - @asset.stale_after).to_i
      days == 1 ? "1 day overdue" : "#{days} days overdue"
    end

    def last_verified_label
      return "never verified" unless @asset.verified_at

      by = @asset.verified_by_agent && "#{(@asset.verified_by_token&.user || @asset.owner).handle}/#{@asset.verified_by_agent}"
      "verified #{@asset.verified_at.to_date.to_fs(:long)}#{" by #{by}" if by}"
    end

    def suggested_review_date
      (Date.current + DEFAULT_INTERVAL).iso8601
    end
  end
end
