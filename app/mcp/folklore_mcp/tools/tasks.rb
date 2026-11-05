module FolkloreMcp
  module Tools
    # Tools over the task queue. Each tool raises the domain's errors and the
    # base class renders them (see DomainErrors).
    module Tasks
      # "handle/agent" of the task's current claimer, or nil.
      def self.claimed_by(task)
        Actor.label(task.claimed_by_user.handle, task.claimed_by_agent) if task.claimed_by_user
      end

      # The slugs of what a task depends on, oldest first, and of the subset
      # that is not done yet. The task's dependencies and their assets must be
      # loaded.
      def self.depends_on(task) = task.dependencies_by_creation.map { |dep| dep.asset.slug }
      def self.blocked_by(task) = task.blockers.map { |dep| dep.asset.slug }
    end
  end
end
