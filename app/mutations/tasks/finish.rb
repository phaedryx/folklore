module Tasks
  # The shared shape of complete and fail: only the (user, agent) holding the
  # claim may finish a task, and finishing clears the claimer and lease. Once
  # finished, the finisher is recorded only by the finishing event, so a
  # repeat call by the same (user, agent) is answered from that event and is
  # a no-op.
  class Finish
    def self.mutate(actor:, slug:, status:, action:, note:, metadata:)
      new(actor:, slug:, status:, action:, note:, metadata:).mutate
    end

    def initialize(actor:, slug:, status:, action:, note:, metadata:)
      @actor = actor
      @slug = slug
      @status = status
      @action = action
      @note = note
      @metadata = metadata
    end

    def mutate
      ActiveRecord::Base.transaction do
        asset, task = Tasks.locked!(@slug)
        if holder?(task)
          task.update!(status: @status, claimed_by_user: nil, claimed_by_token: nil, claimed_by_agent: nil,
                       lease_until: nil, outcome_note: @note)
          Events::Record.mutate(actor: @actor, asset:, action: @action, metadata: @metadata)
        elsif !finisher?(asset, task)
          raise WrongClaimerError, refusal(task)
        end
        asset.reload
      end
    end

    private

    def holder?(task)
      task.status == "in_progress" && task.claimed_by_user_id == @actor.user.id && task.claimed_by_agent == @actor.agent
    end

    def finisher?(asset, task)
      return false unless task.status == @status

      event = Event.where(asset_id: asset.id, action: @action).order(:id).last
      event.present? && event.actor_user_id == @actor.user.id && event.actor_agent == @actor.agent
    end

    def refusal(task)
      you = "#{@actor.handle}/#{@actor.agent}"
      case task.status
      when "pending" then "#{@slug} is not claimed; claim it before finishing it"
      when "in_progress" then "#{@slug} is claimed by #{Tasks.label(task.claimed_by_user_id, task.claimed_by_agent)}, not #{you}"
      else "#{@slug} is #{task.status} and #{you} did not finish it"
      end
    end
  end
end
