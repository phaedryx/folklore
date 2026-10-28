module FolkloreMcp
  module Tools
    module Checkpoints
      class Update < FolkloreMcp::Tool
        tool_name "update_last_session"
        description "Overwrite your session checkpoint with where you are now: open threads, next step, " \
                    "anything the next session needs to resume without re-deriving it. " \
                    "Call this before finishing, and whenever you reach a milestone worth resuming from. " \
                    "Replaces the previous checkpoint (the old text is kept as a version). " \
                    "Each agent has its own checkpoint: pass agent when several agents share one token."
        annotations idempotent: true

        input_schema do
          required(:content).value(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:version).filled(:integer)
        end

        def invoke(content:, server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          result = ::Checkpoints::Write.mutate(actor:, content:)
          asset = result.asset
          verb = result.changed ? "saved to" : "unchanged at"

          text_response("Checkpoint #{verb} #{asset.location} (#{asset.slug})",
                        data: { slug: asset.slug, location: asset.location, version: asset.lock_version })
        end
      end
    end
  end
end
