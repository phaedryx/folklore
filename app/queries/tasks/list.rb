module Tasks
  # Live tasks in a directory and everything below it, oldest first, filtered
  # to one lifecycle status or "all". Pending is the default because the
  # common question is "what is there to pick up"; in_progress is how a
  # resumed agent finds the claim it was holding when it died. A limit, when
  # given, is at most MAX_LIMIT; callers that face an agent pass one.
  class List
    MAX_LIMIT = 500

    def self.query(path_prefix:, status: "pending", tags: [], actor: nil, limit: nil, offset: 0)
      status = status.to_s.presence || "pending"
      raise InvalidStatusError, "status must be one of #{LIST_STATUSES.join(', ')}, got #{status.inspect}" unless LIST_STATUSES.include?(status)
      if limit && !(limit.is_a?(Integer) && limit.between?(1, MAX_LIMIT))
        raise InvalidArgumentError, "limit must be between 1 and #{MAX_LIMIT}, got #{limit.inspect}"
      end
      raise InvalidArgumentError, "offset cannot be negative, got #{offset.inspect}" if offset.to_i.negative?

      scope = Asset.live.joins(:task).under_dir(path_prefix).preload(:tags, :owner, task: :claimed_by_user).order(:created_at, :id)
      scope = scope.where(tasks: { status: }) unless status == "all"
      scope = scope.tagged_with(tags)
      scope = scope.offset(offset.to_i) if offset.to_i.positive?
      limit ? scope.limit(limit) : scope
    end
  end
end
