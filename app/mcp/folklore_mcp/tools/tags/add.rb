module FolkloreMcp
  module Tools
    module Tags
      class Add < FolkloreMcp::Tool
        tool_name "add_tag"
        description "Attach a tag to an asset by slug. Creates the tag if it doesn't exist. Normalizes the name to lowercase."

        input_schema do
          required(:slug).filled(:string)
          required(:tag).filled(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:tag).filled(:string)
          required(:tags).array(:string)
        end

        def invoke(slug:, tag:, server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          asset = ::Tags::Apply.mutate(actor:, slug:, tag:)
          name = Tag.normalize(tag)

          text_response("Tagged #{asset.slug} with #{name}", data: { slug: asset.slug, tag: name, tags: asset.tags.reload.map(&:name).sort })
        end
      end
    end
  end
end
