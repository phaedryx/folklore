module Checkpoints
  # The agent's session checkpoint, or nil if it has never written one.
  # Matched on the exact reserved directory, so an ordinary file that shares
  # the name is never mistaken for it.
  class Read
    def self.query(actor:)
      Asset.live.find_by(owner: actor.user, dir: Checkpoint.dir_for(actor), name: Checkpoint::NAME)
    end
  end
end
