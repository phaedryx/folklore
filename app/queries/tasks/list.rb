module Tasks
  # Live tasks in a directory and everything below it, oldest first, filtered
  # to one lifecycle status or "all". Pending is the default because the
  # common question is "what is there to pick up"; in_progress is how a
  # resumed agent finds the claim it was holding when it died.
  class List
    def self.query(path_prefix:, status: "pending", tags: [], actor: nil)
      status = status.to_s.presence || "pending"
      raise InvalidStatusError, "status must be one of #{LIST_STATUSES.join(', ')}, got #{status.inspect}" unless LIST_STATUSES.include?(status)

      scope = Asset.live.joins(:task).under_dir(path_prefix.to_s).includes(:task, :tags, :owner).order(:created_at, :id)
      scope = scope.where(tasks: { status: }) unless status == "all"
      scope.tagged_with(tags)
    end
  end
end
