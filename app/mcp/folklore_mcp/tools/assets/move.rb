module FolkloreMcp
  module Tools
    module Assets
      class Move < FolkloreMcp::Tool
        tool_name "move"
        description "Move an asset by slug to another directory in your workspace, renaming it if " \
                    "name is given. The slug stays, so [[slug]] links keep working. 'path' is the " \
                    "directory only."
        annotations idempotent: true

        input_schema do
          required(:slug).filled(:string)
          required(:path).filled(:string)
          optional(:name).filled(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:version).filled(:integer)
        end

        def invoke(slug:, path:, server_context:, name: nil, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Assets::Move.mutate(actor:, slug:, path:, name:)

          text_response("Moved #{asset.slug} to #{asset.location}",
                        data: { slug: asset.slug, location: asset.location, version: asset.lock_version })
        end
      end
    end
  end
end
