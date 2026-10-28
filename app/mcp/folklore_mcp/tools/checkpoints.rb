module FolkloreMcp
  module Tools
    # Tools over the per-agent session checkpoint.
    module Checkpoints
      FolkloreMcp::Tool.user_error(::Checkpoints::EmptyContentError, "Invalid")
      FolkloreMcp::Tool.user_error(::Checkpoints::NoAgentError, "Invalid")

      def self.location(actor)
        "#{Checkpoint.dir_for(actor)}/#{Checkpoint::NAME}"
      end
    end
  end
end
