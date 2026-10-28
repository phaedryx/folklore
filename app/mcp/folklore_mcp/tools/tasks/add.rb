module FolkloreMcp
  module Tools
    module Tasks
      class Add < FolkloreMcp::Tool
        tool_name "add_task"
        description "Create a new task at the given path, status 'pending'. 'path' is the DIRECTORY only " \
                    "and must be under your own workspace; 'name' is the leaf. Tags pass through as given. " \
                    "Claim it with claim_task, finish it with complete_task or fail_task."

        input_schema do
          required(:path).filled(:string)
          required(:name).filled(:string)
          optional(:content).value(:string)
          optional(:content_type).filled(:string)
          optional(:tags).array(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:status).filled(:string)
        end

        def invoke(path:, name:, server_context:, content: nil, content_type: nil, tags: [])
          actor = actor_from(server_context)
          asset = ::Tasks::Add.mutate(actor:, path:, name:, content:, content_type:, tags:)

          text_response("Added task #{asset.slug} at #{asset.location}",
                        data: { slug: asset.slug, location: asset.location, status: asset.task.status })
        end
      end
    end
  end
end
