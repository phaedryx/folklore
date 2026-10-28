module Events
  # The one place an event row is written. Every mutation calls this inside
  # its own transaction, so the event and the write it describes commit or
  # roll back together. Nothing is broadcast.
  class Record
    def self.mutate(actor:, action:, asset: nil, metadata: {})
      Event.create!(
        actor_user: actor.user,
        actor_token: actor.token,
        actor_agent: actor.agent,
        asset:,
        action:,
        metadata:
      )
    end
  end
end
