module FolkloreMcp
  module Tools
    # Tools over the task queue. The domain's errors are registered here once,
    # so each tool raises and the base class renders.
    module Tasks
      FolkloreMcp::Tool.user_error(::Tasks::NotATaskError, "Not a task")
      FolkloreMcp::Tool.user_error(::Tasks::AlreadyClaimedError, "Already claimed")
      FolkloreMcp::Tool.user_error(::Tasks::NoPendingTaskError, "No pending task")
      FolkloreMcp::Tool.user_error(::Tasks::WrongClaimerError, "Wrong claimer")
      FolkloreMcp::Tool.user_error(::Tasks::ReasonRequiredError, "Invalid")
      FolkloreMcp::Tool.user_error(::Tasks::InvalidStatusError, "Invalid")
      FolkloreMcp::Tool.user_error(::Tasks::InvalidLeaseError, "Invalid")
      FolkloreMcp::Tool.user_error(::Tasks::InvalidArgumentError, "Invalid")

      # "handle/agent" of the task's current claimer, or nil.
      def self.claimed_by(task)
        Actor.label(task.claimed_by_user.handle, task.claimed_by_agent) if task.claimed_by_user
      end
    end
  end
end
