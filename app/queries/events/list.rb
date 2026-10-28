module Events
  # The activity feed, newest first; or, with `since_id`, the events after a
  # cursor oldest first so a reader can walk forward without gaps; or, with
  # `before_id`, the events before a cursor newest first, for paging back.
  class List
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 200

    def self.query(actor: nil, tag: nil, since: nil, before: nil, since_id: nil, before_id: nil, limit: DEFAULT_LIMIT)
      new(actor:, tag:, since:, before:, since_id:, before_id:, limit:).query
    end

    # An event id from a caller: an Integer or a string of digits. Anything
    # else is an error rather than a silent 0, which would read from the start.
    def self.parse_cursor(name, value)
      return nil if value.nil? || value == ""
      return value if value.is_a?(Integer) && !value.negative?
      return value.to_i if value.is_a?(String) && value.match?(/\A\d+\z/)

      raise InvalidCursorError, "#{name} must be a non-negative integer, got #{value.inspect}"
    end

    def initialize(actor:, tag:, since:, before:, since_id:, limit:, before_id: nil)
      @actor = actor
      @tag = tag
      @since = since
      @before = before
      @since_id = self.class.parse_cursor(:since_id, since_id)
      @before_id = self.class.parse_cursor(:before_id, before_id)
      @limit = [ limit.to_i, MAX_LIMIT ].min
      @limit = DEFAULT_LIMIT if @limit <= 0
    end

    def query
      scope = Event.limit(@limit).includes(:actor_user, :asset)
      scope = @since_id ? scope.where("events.id > ?", @since_id).order(id: :asc) : scope.order(id: :desc)
      scope = scope.where("events.id < ?", @before_id) if @before_id
      scope = scope.where(actor_filter) if @actor
      scope = scope.where("events.created_at >= ?", @since) if @since
      scope = scope.where("events.created_at < ?", @before) if @before
      scope = scope.where(asset_id: assets_with_tag(@tag).select(:id)) if @tag
      scope
    end

    private

    # "handle" or "handle/agent". An unknown handle matches nothing rather
    # than everything.
    def actor_filter
      case @actor
      when Actor then { actor_user_id: @actor.user.id, actor_agent: @actor.agent }
      when User then { actor_user_id: @actor.id }
      else
        handle, agent = @actor.to_s.split("/", 2)
        user_id = User.where(handle:).pick(:id) || -1
        agent.present? ? { actor_user_id: user_id, actor_agent: agent } : { actor_user_id: user_id }
      end
    end

    def assets_with_tag(name)
      tag = Tag.find_by(name: name.to_s.downcase.strip)
      return Asset.none unless tag

      Asset.joins(:asset_tags).where(asset_tags: { tag_id: tag.id })
    end
  end
end
