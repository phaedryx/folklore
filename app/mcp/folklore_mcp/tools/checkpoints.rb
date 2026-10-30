module FolkloreMcp
  module Tools
    # Tools over the per-agent session checkpoint.
    module Checkpoints
      def self.location(actor)
        "#{Checkpoint.dir_for(actor)}/#{Checkpoint::NAME}"
      end
    end
  end
end
