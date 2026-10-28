module FolkloreMcp
  module Tools
    module Assets
      class SetStaleAfter < FolkloreMcp::Tool
        tool_name "set_stale_after"
        description "Set the date after which an asset should be re-checked, without claiming it still holds. " \
                    "Use this when you know something needs revisiting by a date but have not re-read it; use " \
                    "`verify` when you have. Pass an empty stale_after to clear the review date. " \
                    "Find overdue assets with search(stale: true)."
        annotations idempotent: true

        input_schema do
          required(:slug).filled(:string)
          required(:stale_after).value(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:stale_after).maybe(:string)
        end

        def invoke(slug:, stale_after:, server_context:)
          actor = actor_from(server_context)
          asset = ::Assets::SetStaleAfter.mutate(actor:, slug:, stale_after:)

          text = asset.stale_after ? "#{asset.slug} due for re-check after #{asset.stale_after.iso8601}"
                                   : "Cleared the review date on #{asset.slug}"
          text_response(text, data: { slug: asset.slug, stale_after: asset.stale_after&.iso8601 })
        end
      end
    end
  end
end
