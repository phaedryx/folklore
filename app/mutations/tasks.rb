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
  # An outcome note over Task::MAX_NOTE_LENGTH: complete's note or fail's reason.
  InvalidNoteError = Class.new(Error)
  NoteTooLongError = Class.new(InvalidNoteError)
  ReasonTooLongError = Class.new(InvalidNoteError)

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

  # Refuses an outcome note over Task::MAX_NOTE_LENGTH; `label` is what the
  # caller called it, and `error` the error that names it (complete's note,
  # fail's reason).
  def self.validate_note!(note, label, error: NoteTooLongError)
    return if note.nil? || note.length <= Task::MAX_NOTE_LENGTH

    raise error, "#{label} is #{note.length} characters, over the #{Task::MAX_NOTE_LENGTH} character limit"
  end

  # "handle/agent" for a claimer or an event's actor.
  def self.label(user_id, agent)
    Actor.label(User.where(id: user_id).pick(:handle), agent)
  end

  # The claimer's label, for a refusal to `actor`. The token is part of the
  # claim, so the holder may carry the caller's own label; then the token is
  # what differs, and the refusal says so.
  def self.holder(task, actor)
    held_by = label(task.claimed_by_user_id, task.claimed_by_agent)
    held_by == actor.label && task.claimed_by_token_id != actor.token&.id ? "#{held_by} on another token" : held_by
  end
end
