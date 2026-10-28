# The task domain's errors, shared by its queries and mutations so callers
# (MCP tools, the web) map each one once.
module Tasks
  Error = Class.new(StandardError)
  NotATaskError = Class.new(Error)
  AlreadyClaimedError = Class.new(Error)
  NoPendingTaskError = Class.new(Error)
  WrongClaimerError = Class.new(Error)
  ReasonRequiredError = Class.new(Error)
  InvalidStatusError = Class.new(Error)
  InvalidLeaseError = Class.new(Error)
  InvalidArgumentError = Class.new(Error)

  # Statuses a listing accepts: the task lifecycle plus "all".
  LIST_STATUSES = (Task::STATUSES + %w[all]).freeze

  # The live task behind a slug, row-locked for the rest of the caller's
  # transaction. Lifecycle writes touch only the facet row and an event, so
  # any member may make them (design 9a); there is no workspace check here.
  def self.locked!(slug)
    asset = Asset.live.find_by(slug:)
    raise Assets::NotFoundError, slug unless asset

    task = Task.lock.find_by(asset_id: asset.id)
    raise NotATaskError, slug unless task

    [ asset, task ]
  end

  # "handle/agent" for a claimer or an event's actor.
  def self.label(user_id, agent)
    Actor.label(User.where(id: user_id).pick(:handle), agent)
  end
end
