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
        raise NotANoteError, "#{@slug} is a task; use claim_task, complete_task or fail_task" if asset.task?

        return asset if asset.status == status

        # A lifecycle marker, not an edit: updated_at, updated_by and
        # lock_version describe the last edit and stay put. Who set it is in
        # the event.
        asset.update_columns(status:)
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
