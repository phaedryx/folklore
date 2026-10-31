module FolkloreMcp
  module Tools
    module Assets
      class Upsert < FolkloreMcp::Tool
        tool_name "upsert"
        description "Update the live asset at path + name, keeping the old text as a version, or " \
                    "create it there. 'path' and 'name' as in create."
        annotations idempotent: true, destructive: true

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
          required(:created).filled(:bool)
        end

        def invoke(path:, name:, server_context:, content: nil, content_type: nil, tags: nil, agent: nil)
          actor = actor_from(server_context, agent:)
          result = ::Assets::Upsert.mutate(actor:, path:, name:, content:, content_type:, tags:)
          asset = result.asset

          text = result.created ? "Created #{asset.slug} at #{asset.location}" : "Updated #{asset.slug}"
          text_response(text, data: { slug: asset.slug, location: asset.location, version: asset.lock_version, created: result.created })
        end
      end
    end
  end
end
