module FolkloreMcp
  module Tools
    module Assets
      class Update < FolkloreMcp::Tool
        tool_name "update"
        description "Update an asset by slug, changing only what you pass; an empty content clears it. " \
                    "A content change keeps the old text as a version. 'name' renames it (a leaf, not a " \
                    "path; use move for that). Pass expected_version (read's version) to get Conflict " \
                    "if someone else edited first."
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
