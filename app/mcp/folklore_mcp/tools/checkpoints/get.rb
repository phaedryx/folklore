module FolkloreMcp
  module Tools
    module Checkpoints
      class Get < FolkloreMcp::Tool
        tool_name "get_last_session"
        description "Read your session checkpoint: where you left off last time. " \
                    "Call this FIRST, before any other tool, at the start of every session. " \
                    "Returns the whole checkpoint in one read; pair with update_last_session before you finish. " \
                    "Each agent has its own checkpoint: pass agent when several agents share one token."
        annotations read_only: true, idempotent: true

        input_schema do
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:agent).filled(:string)
          required(:location).filled(:string)
          optional(:slug).filled(:string)
          optional(:updated_at).filled(:string)
          required(:content).maybe(:string)
        end

        def invoke(server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          location = Checkpoints.location(actor)
          who = actor.label
          checkpoint = ::Checkpoints::Read.query(actor:)

          unless checkpoint
            return text_response("No checkpoint yet for #{who}. Call update_last_session before finishing.",
                                 data: { agent: who, location:, content: nil })
          end

          json_response(agent: who, location:, slug: checkpoint.slug, updated_at: checkpoint.updated_at.iso8601,
                        content: checkpoint.content)
        end
      end
    end
  end
end
