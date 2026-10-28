module Checkpoints
  # Overwrites the agent's session checkpoint in place. Upsert keeps the
  # reserved location holding exactly one live asset, and the displaced text
  # survives as a version, so the checkpoint has a history.
  class Write
    EmptyContentError = Checkpoints::EmptyContentError

    def self.mutate(actor:, content:)
      # An empty checkpoint is a mistake, not an intent: refusing it keeps an
      # agent from reporting a save that wiped where it left off.
      raise EmptyContentError, "checkpoint content cannot be empty" if content.to_s.strip.empty?
      raise NoAgentError, "web sessions have no checkpoint; checkpoints belong to agents" if actor.agent == Actor::WEB_AGENT

      Assets::Upsert.mutate(actor:, path: Checkpoint.dir_for(actor), name: Checkpoint::NAME,
                            content:, content_type: "text/markdown", reserved: true).asset
    end
  end
end
