module Assets
  # The note lifecycle: open, done, or nothing. Tasks have their own
  # lifecycle on the tasks facet and refuse this one.
  class SetStatus
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    NotANoteError = Assets::NotANoteError
    InvalidStatusError = Assets::InvalidStatusError

    def self.mutate(actor:, slug:, status:)
      new(actor:, slug:, status:).mutate
    end

    def initialize(actor:, slug:, status:)
      @actor = actor
      @slug = slug
      @status = status
    end

    def mutate
      status = normalized_status

      ActiveRecord::Base.transaction do
        asset = Assets.writable!(@slug, @actor)
        asset.lock!
        raise NotANoteError, "#{@slug} is a task; use claim_task, complete_task or fail_task" if asset.task?

        asset.update!(status:, updated_by_token: @actor.token, updated_by_agent: @actor.agent)
        Events::Record.mutate(actor: @actor, asset:, action: "asset_status_set", metadata: { "status" => status })
        asset
      end
    end

    private

    def normalized_status
      value = @status.to_s.strip
      return nil if value.empty?
      raise InvalidStatusError, "status must be one of: #{Asset::NOTE_STATUSES.join(', ')}" unless Asset::NOTE_STATUSES.include?(value)

      value
    end
  end
end
