module FolkloreMcp
  module Tools
    module Assets
      class SetStatus < FolkloreMcp::Tool
        tool_name "set_status"
        description "Set a lifecycle status ('open' or 'done') on a note, or clear it (omit/empty status). " \
                    "Not valid for tasks — those use claim_task, complete_task and fail_task."
        annotations idempotent: true

        input_schema do
          required(:slug).filled(:string)
          optional(:status).value(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:status).maybe(:string)
        end

        def invoke(slug:, server_context:, status: nil)
          actor = actor_from(server_context)
          asset = ::Assets::SetStatus.mutate(actor:, slug:, status:)

          text_response("Set status of #{asset.slug} to #{asset.status || 'none'}", data: { slug: asset.slug, status: asset.status })
        end
      end
    end
  end
end
