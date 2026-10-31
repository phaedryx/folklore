module Versions
  # The one place a version row is written for a live edit: keeps the
  # asset's current content before a caller overwrites it. Called inside the
  # caller's transaction, under its row lock. A bundle import loads historical
  # versions in bulk instead.
  class Snapshot
    def self.mutate(actor:, asset:)
      Version.create!(
        asset:,
        content: asset.content,
        content_type: asset.content_type,
        actor_user: actor.user,
        actor_token: actor.token,
        actor_agent: actor.agent
      )
    end
  end
end
