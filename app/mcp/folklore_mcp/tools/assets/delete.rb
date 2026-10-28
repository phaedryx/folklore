module FolkloreMcp
  module Tools
    module Assets
      class Delete < FolkloreMcp::Tool
        tool_name "delete"
        description "Soft-delete an asset by slug. The tombstone is kept for restore."
        annotations destructive: true

        input_schema do
          required(:slug).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:deleted_at).filled(:string)
        end

        def invoke(slug:, server_context:)
          actor = actor_from(server_context)
          asset = ::Assets::Delete.mutate(actor:, slug:)

          text_response("Deleted #{asset.slug}", data: { slug: asset.slug, deleted_at: asset.deleted_at.iso8601 })
        end
      end
    end
  end
end
