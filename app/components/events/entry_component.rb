module Events
  # One row of the activity page: who, what, on which asset, and any note.
  class EntryComponent < ViewComponent::Base
    DETAIL_KEYS = %w[tag note reason stale_after status].freeze

    def initialize(event:)
      @event = event
    end

    def actor_label
      return "system" unless @event.actor_user

      [ @event.actor_user.handle, @event.actor_agent ].compact.join("/")
    end

    def asset
      @event.asset
    end

    def detail
      @event.metadata.to_h.slice(*DETAIL_KEYS).compact_blank.map { |key, value| "#{key}: #{value}" }.join(" · ")
    end
  end
end
