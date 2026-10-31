module FolkloreMcp
  module Tools
    module Tags
      class Remove < FolkloreMcp::Tool
        tool_name "remove_tag"
        description "Detach a tag from an asset by slug. A tag not there is not an error: changed is false."

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
          result = ::Tags::Remove.mutate(actor:, slug:, tag:)
          asset = result.asset
          name = Tag.normalize(tag)
          text = result.changed ? "Removed tag #{name} from #{asset.slug}" : "#{asset.slug} does not have tag #{name}"

          text_response(text, data: { slug: asset.slug, tag: name, tags: asset.tags.reload.map(&:name).sort, changed: result.changed })
        end
      end
    end
  end
end
