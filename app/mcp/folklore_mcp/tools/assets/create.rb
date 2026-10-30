module FolkloreMcp
  module Tools
    module Assets
      class Create < FolkloreMcp::Tool
        tool_name "create"
        description "Create an asset. 'path' is the directory, starting with your handle (a trailing " \
                    "filename is rejected); 'name' is the leaf (no '/' or whitespace, not '.' or '..'). " \
                    "Conflict if the name is taken there; update an existing asset by slug with update."

        input_schema do
          required(:path).filled(:string)
          required(:name).filled(:string)
          optional(:content).value(:string)
          optional(:content_type).filled(:string)
          optional(:tags).array(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:version).filled(:integer)
        end

        def invoke(path:, name:, server_context:, content: nil, content_type: nil, tags: [], agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Assets::Create.mutate(actor:, path:, name:, content:, content_type:, tags:)

          text_response("Created #{asset.slug} at #{asset.location}",
                        data: { slug: asset.slug, location: asset.location, version: asset.lock_version })
        end
      end
    end
  end
end
