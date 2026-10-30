module FolkloreMcp
  module Tools
    module Assets
      class Restore < FolkloreMcp::Tool
        tool_name "restore"
        description "Restore a soft-deleted asset by slug. Conflict if a live asset now has its location."

        input_schema do
          required(:slug).filled(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
        end

        def invoke(slug:, server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Assets::Restore.mutate(actor:, slug:)

          text_response("Restored #{asset.slug}", data: { slug: asset.slug, location: asset.location })
        end
      end
    end
  end
end
