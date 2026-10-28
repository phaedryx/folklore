module Tasks
  # Tasks as rows: the asset, where it lives, its status and, while it is
  # claimed, who holds it and until when. The claim columns are cleared when
  # a task leaves in_progress, so a present claimer is always a live claim.
  class ListComponent < ViewComponent::Base
    def initialize(tasks:)
      @tasks = tasks
    end

    def claimer(task)
      facet = task.task
      return unless facet.claimed_by_user

      Actor.label(facet.claimed_by_user.handle, facet.claimed_by_agent)
    end

    def lease_label(task) = task.task.lease_expired? ? "lease expired" : "lease until"

    def lease_time(task)
      lease_until = task.task.lease_until.utc
      time_tag lease_until, lease_until.strftime("%Y-%m-%d %H:%M UTC")
    end
  end
end
