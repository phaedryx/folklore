module FolkloreMcp
  module Tools
    module Tasks
      class Add < FolkloreMcp::Tool
        tool_name "add_task"
        description "Create a new task at the given path, status 'pending'. 'path' is the DIRECTORY only " \
                    "and must be under your own workspace; 'name' is the leaf. Tags pass through as given. " \
                    "depends_on lists slugs of tasks that must be done before this one can be claimed; " \
                    "it is set here and cannot be changed later, and a slug that is not a task refuses " \
                    "the call. Claim it with claim_task, finish it with complete_task or fail_task."

        input_schema do
          required(:path).filled(:string)
          required(:name).filled(:string)
          optional(:content).value(:string)
          optional(:content_type).filled(:string)
          optional(:tags).array(:string)
          optional(:depends_on).array(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:status).filled(:string)
        end

        def invoke(path:, name:, server_context:, content: nil, content_type: nil, tags: [], depends_on: [], agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Tasks::Add.mutate(actor:, path:, name:, content:, content_type:, tags:, depends_on:)

          text_response("Added task #{asset.slug} at #{asset.location}",
                        data: { slug: asset.slug, location: asset.location, status: asset.task.status })
        end
      end
    end
  end
end
