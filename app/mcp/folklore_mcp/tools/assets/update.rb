module FolkloreMcp
  module Tools
    module Assets
      class Update < FolkloreMcp::Tool
        tool_name "update"
        description "Update an existing asset by slug. Snapshots prior content into versions on " \
                    "content change; an empty content clears it, omitting it leaves it alone. " \
                    "'name', when renaming, is the leaf only (no whitespace, no '/', not '.' or " \
                    "'..') — it is not a path. Pass expected_version (from read's version field) " \
                    "to refuse the write with Conflict if someone else edited first. Not found if " \
                    "archived."
        annotations destructive: true

        input_schema do
          required(:slug).filled(:string)
          optional(:content).value(:string)
          optional(:name).filled(:string)
          optional(:content_type).filled(:string)
          optional(:tags).array(:string)
          optional(:expected_version).filled(:integer)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:version).filled(:integer)
        end

        def invoke(slug:, server_context:, content: nil, name: nil, content_type: nil, tags: nil, expected_version: nil, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Assets::Update.mutate(actor:, slug:, content:, name:, content_type:, tags:, expected_version:)

          text_response("Updated #{asset.slug}",
                        data: { slug: asset.slug, location: asset.location, version: asset.lock_version })
        end
      end
    end
  end
end
