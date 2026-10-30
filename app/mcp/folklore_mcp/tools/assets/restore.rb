module FolkloreMcp
  module Tools
    module Assets
      class Restore < FolkloreMcp::Tool
        tool_name "restore"
        description "Restore an archived asset by slug; Conflict if a live asset now has its location. " \
                    "With version (an id from versions), put that version's content back on a live " \
                    "asset instead; the content it replaces is kept as a version."
        annotations destructive: true

        input_schema do
          required(:slug).filled(:string)
          optional(:version).filled(:integer)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          optional(:version).filled(:integer)
        end

        def invoke(slug:, server_context:, version: nil, agent: nil)
          actor = actor_from(server_context, agent:)
          if version
            asset = ::Versions::Restore.mutate(actor:, slug:, version_id: version)
            return text_response("Restored #{asset.slug} to version #{version}",
                                 data: { slug: asset.slug, location: asset.location, version: asset.lock_version })
          end

          asset = ::Assets::Restore.mutate(actor:, slug:)
          text_response("Restored #{asset.slug}", data: { slug: asset.slug, location: asset.location })
        end
      end
    end
  end
end
