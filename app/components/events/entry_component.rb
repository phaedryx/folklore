module Events
  # One row of the activity page: who, what, on which asset, and any note.
  class EntryComponent < ViewComponent::Base
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
      Events::Detail.call(@event)
    end
  end
end
