module FolkloreMcp
  module Tools
    module Tasks
      class Complete < FolkloreMcp::Tool
        tool_name "complete_task"
        description "Mark a task you hold done, with an optional outcome note. Only the (you, token, agent) " \
                    "that claimed it can complete it; use the same token and agent you claimed with. " \
                    "Anyone else gets Wrong claimer."
        annotations idempotent: true

        input_schema do
          required(:slug).filled(:string)
          optional(:note).value(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:status).filled(:string)
          required(:note).maybe(:string)
        end

        def invoke(slug:, server_context:, note: nil, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Tasks::Complete.mutate(actor:, slug:, note:)

          text_response("Completed #{asset.slug}",
                        data: { slug: asset.slug, status: asset.task.status, note: asset.task.outcome_note })
        end
      end
    end
  end
end
