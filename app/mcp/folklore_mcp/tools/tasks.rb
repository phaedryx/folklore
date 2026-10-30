module FolkloreMcp
  module Tools
    # Tools over the task queue. Each tool raises the domain's errors and the
    # base class renders them (see DomainErrors).
    module Tasks
      # "handle/agent" of the task's current claimer, or nil.
      def self.claimed_by(task)
        Actor.label(task.claimed_by_user.handle, task.claimed_by_agent) if task.claimed_by_user
      end
    end
  end
end
