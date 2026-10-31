module FolkloreMcp
  module Tools
    module Assets
      class Append < FolkloreMcp::Tool
        tool_name "append"
        description "Append text to an existing asset by slug, on a new line. " \
                    "Snapshots prior content into versions. Not found if archived."

        input_schema do
          required(:slug).filled(:string)
          required(:text).filled(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:version).filled(:integer)
        end

        def invoke(slug:, text:, server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Assets::Append.mutate(actor:, slug:, text:)

          text_response("Appended to #{asset.slug}", data: { slug: asset.slug, version: asset.lock_version })
        end
      end
    end
  end
end
