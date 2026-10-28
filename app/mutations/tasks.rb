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

  # Statuses a listing accepts: the task lifecycle plus "all".
  LIST_STATUSES = (Task::STATUSES + %w[all]).freeze
end
