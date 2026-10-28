module FolkloreMcp
  module Tools
    module Assets
      class Create < FolkloreMcp::Tool
        tool_name "create"
        description "Create a new asset at the given path. Use 'update' to modify an existing asset " \
                    "by slug. 'path' is the DIRECTORY only (no trailing filename or known file " \
                    "extension — those are rejected); 'name' is the leaf (no whitespace, no '/', " \
                    "not '.' or '..'). Fails with Conflict if a live asset already has that name there."

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
          required(:version).filled(:integer)
        end

        def invoke(path:, name:, server_context:, content: nil, content_type: nil, tags: [])
          actor = actor_from(server_context)
          asset = ::Assets::Create.mutate(actor:, path:, name:, content:, content_type:, tags:)

          text_response("Created #{asset.slug} at #{asset.location}",
                        data: { slug: asset.slug, location: asset.location, version: asset.lock_version })
        end
      end
    end
  end
end
