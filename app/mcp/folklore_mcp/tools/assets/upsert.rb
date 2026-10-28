module FolkloreMcp
  module Tools
    module Assets
      class Upsert < FolkloreMcp::Tool
        tool_name "upsert"
        description "Create-or-update an asset by path + name. Updates the live asset at that " \
                    "path + name if one exists (snapshotting prior content), otherwise creates it. " \
                    "'path' is the DIRECTORY only (no trailing filename or known file extension — " \
                    "those are rejected); 'name' is the leaf (no whitespace, no '/', not '.' or '..')."
        annotations idempotent: true, destructive: true

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
          required(:created).filled(:bool)
        end

        def invoke(path:, name:, server_context:, content: nil, content_type: nil, tags: nil)
          actor = actor_from(server_context)
          result = ::Assets::Upsert.mutate(actor:, path:, name:, content:, content_type:, tags:)
          asset = result.asset

          text = result.created ? "Created #{asset.slug} at #{asset.location}" : "Updated #{asset.slug}"
          text_response(text, data: { slug: asset.slug, location: asset.location, version: asset.lock_version, created: result.created })
        end
      end
    end
  end
end
