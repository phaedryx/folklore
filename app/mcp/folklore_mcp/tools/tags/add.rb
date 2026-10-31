module FolkloreMcp
  module Tools
    module Tags
      class Add < FolkloreMcp::Tool
        tool_name "add_tag"
        description "Attach a tag to an asset by slug, creating the tag if needed. Names are lowercased. A tag already there is not an error: changed is false."

        input_schema do
          required(:slug).filled(:string)
          required(:tag).filled(:string)
          optional(:agent).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:tag).filled(:string)
          required(:tags).array(:string)
          required(:changed).filled(:bool)
        end

        def invoke(slug:, tag:, server_context:, agent: nil)
          actor = actor_from(server_context, agent:)
          result = ::Tags::Apply.mutate(actor:, slug:, tag:)
          asset = result.asset
          name = Tag.normalize(tag)
          text = result.changed ? "Tagged #{asset.slug} with #{name}" : "#{asset.slug} already has tag #{name}"

          text_response(text, data: { slug: asset.slug, tag: name, tags: asset.tags.reload.map(&:name).sort, changed: result.changed })
        end
      end
    end
  end
end
