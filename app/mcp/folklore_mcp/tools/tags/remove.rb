module FolkloreMcp
  module Tools
    module Tags
      class Remove < FolkloreMcp::Tool
        tool_name "remove_tag"
        description "Detach a tag from an asset by slug. The tag itself is not deleted even if it becomes orphaned."

        input_schema do
          required(:slug).filled(:string)
          required(:tag).filled(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:tag).filled(:string)
          required(:tags).array(:string)
        end

        def invoke(slug:, tag:, server_context:)
          actor = actor_from(server_context)
          asset = ::Tags::Remove.mutate(actor:, slug:, tag:)
          name = Tag.normalize(tag)

          text_response("Removed tag #{name} from #{asset.slug}", data: { slug: asset.slug, tag: name, tags: asset.tags.reload.map(&:name).sort })
        end
      end
    end
  end
end
