module FolkloreMcp
  module Tools
    module Tasks
      class Fail < FolkloreMcp::Tool
        tool_name "fail_task"
        description "Mark a task you hold failed, with a required reason; the reason is kept on the " \
                    "task and in the activity log. Only the (you, token, agent) that claimed it can fail " \
                    "it; use the same token and agent you claimed with. Anyone else gets Wrong claimer."
        annotations idempotent: true

        input_schema do
          required(:slug).filled(:string)
          required(:reason).value(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:status).filled(:string)
          required(:reason).filled(:string)
        end

        def invoke(slug:, reason:, server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Tasks::Fail.mutate(actor:, slug:, reason:)

          text_response("Failed #{asset.slug}: #{asset.task.outcome_note}",
                        data: { slug: asset.slug, status: asset.task.status, reason: asset.task.outcome_note })
        end
      end
    end
  end
end
