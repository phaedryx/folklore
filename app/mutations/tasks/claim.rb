module Tasks
  # Claims a task for the actor's (user, token, agent) under a lease. The
  # token is part of the claim: another token acting as the same agent label
  # is a different claimer.
  #
  # By slug, the task is claimable when it is pending, when its lease has
  # expired, or when the actor already holds it (which renews the lease).
  # Without a slug, the oldest pending or lease-expired task under
  # `path_prefix` (and carrying every tag in `tags`) is claimed, skipping rows
  # another claimer has locked, so concurrent agents take different tasks.
  #
  # Either way the claim is one UPDATE whose CTE locks the row and returns its
  # previous claimer, and the events it implies commit in the same
  # transaction. Lease times are computed here rather than with now(), so the
  # app clock is the only clock.
  class Claim
    DEFAULT_LEASE_SECONDS = 1800
    MAX_LEASE_SECONDS = 7 * 24 * 3600

    # The current claimer is the actor. A web actor has no token, so the token
    # comparison treats two NULLs as equal.
    HOLDER = <<~SQL.squish.freeze
      prev.claimed_by_user_id = :user_id AND prev.claimed_by_agent = :agent
      AND prev.claimed_by_token_id IS NOT DISTINCT FROM :token_id
    SQL

    ELIGIBLE = <<~SQL.squish.freeze
      prev.status = 'pending'
      OR (prev.status = 'in_progress' AND (prev.lease_until < :now OR (#{HOLDER})))
    SQL

    def self.mutate(actor:, slug: nil, path_prefix: nil, tags: [], lease_seconds: DEFAULT_LEASE_SECONDS)
      new(actor:, slug:, path_prefix:, tags:, lease_seconds:).mutate
    end

    def initialize(actor:, slug:, path_prefix:, tags:, lease_seconds:)
      @actor = actor
      @slug = slug.presence
      @path_prefix = path_prefix.to_s.delete_suffix("/").presence
      @tags = Array(tags)
      @lease_seconds = lease_seconds.nil? ? DEFAULT_LEASE_SECONDS : lease_seconds
    end

    def mutate
      validate!
      now = Time.current

      ActiveRecord::Base.transaction do
        prev = @slug ? claim_by_slug(now) : claim_next(now)
        asset = Asset.find(prev.asset_id)
        record_events(asset, prev)
        asset.reload
      end
    end

    private

    def validate!
      raise InvalidArgumentError, "pass a slug, or a path_prefix to claim the next pending task" unless @slug || @path_prefix
      return if @lease_seconds.is_a?(Integer) && @lease_seconds.between?(1, MAX_LEASE_SECONDS)

      raise InvalidLeaseError, "lease_seconds must be a whole number from 1 to #{MAX_LEASE_SECONDS}, got #{@lease_seconds.inspect}"
    end

    def claim_by_slug(now)
      asset = Asset.live.find_by(slug: @slug)
      raise Assets::NotFoundError, @slug unless asset
      raise NotATaskError, @slug unless Task.exists?(asset_id: asset.id)

      target = Task.where(asset_id: asset.id).lock("FOR UPDATE")
      claim(target, now) or raise AlreadyClaimedError, unavailable(asset)
    end

    def claim_next(now)
      candidates = Asset.live.under_dir(@path_prefix).tagged_with(@tags).select(:id)
      target = Task.joins(:asset)
                   .where(asset_id: candidates)
                   .where("tasks.status = 'pending' OR (tasks.status = 'in_progress' AND tasks.lease_until < ?)", now)
                   .order("assets.created_at", "assets.id")
                   .limit(1)
                   .lock("FOR UPDATE OF tasks SKIP LOCKED")
      claim(target, now) or raise NoPendingTaskError, "nothing to claim under #{@path_prefix}"
    end

    # Runs the claiming UPDATE over the (at most one) row `target` locks and
    # returns that row's previous state, or nil when it was not claimable.
    def claim(target, now)
      locked = target.select("tasks.asset_id, tasks.status, tasks.claimed_by_user_id, tasks.claimed_by_token_id, " \
                             "tasks.claimed_by_agent, tasks.lease_until")
      sql = <<~SQL
        WITH prev AS (#{locked.to_sql})
        UPDATE tasks
           SET status = 'in_progress',
               claimed_by_user_id = :user_id,
               claimed_by_token_id = :token_id,
               claimed_by_agent = :agent,
               lease_until = :lease_until,
               attempts = tasks.attempts + CASE WHEN prev.status = 'in_progress' AND #{HOLDER} THEN 0 ELSE 1 END,
               updated_at = :now
          FROM prev
         WHERE tasks.asset_id = prev.asset_id AND (#{ELIGIBLE})
        RETURNING prev.asset_id, prev.status AS prev_status, prev.claimed_by_user_id AS prev_user_id,
                  prev.claimed_by_token_id AS prev_token_id, prev.claimed_by_agent AS prev_agent,
                  prev.lease_until AS prev_lease_until
      SQL
      Task.find_by_sql([ sql, { user_id: @actor.user.id, token_id: @actor.token&.id, agent: @actor.agent,
                                lease_until: now + @lease_seconds, now: } ]).first
    end

    def record_events(asset, prev)
      held_before = prev.prev_status == "in_progress"
      renewal = held_before && prev.prev_user_id == @actor.user.id && prev.prev_agent == @actor.agent &&
                prev.prev_token_id == @actor.token&.id
      metadata = { "lease_until" => asset.task.reload.lease_until.iso8601 }

      if renewal
        # Not a new attempt, but the lease moved: the log shows every extension.
        Events::Record.mutate(actor: @actor, asset:, action: "task_claimed", metadata: metadata.merge("renewal" => true))
        return
      end

      if held_before
        Events::Record.mutate(actor: @actor, asset:, action: "task_lease_expired", metadata: {
          "claimed_by" => Tasks.label(prev.prev_user_id, prev.prev_agent),
          "lease_until" => prev.prev_lease_until.in_time_zone.iso8601
        })
      end
      Events::Record.mutate(actor: @actor, asset:, action: "task_claimed", metadata:)
    end

    def unavailable(asset)
      task = Task.find(asset.id)
      return "#{@slug} is #{task.status}" unless task.status == "in_progress"

      "#{@slug} is claimed by #{Tasks.holder(task, @actor)} until #{task.lease_until.iso8601}"
    end
  end
end
