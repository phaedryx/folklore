module FolkloreMcp
  module Tools
    module Assets
      class Verify < FolkloreMcp::Tool
        tool_name "verify"
        description "Record that an asset's content still holds, and optionally set stale_after — the date " \
                    "after which it should be re-checked. Verification is not an edit: it leaves updated_at " \
                    "and version history alone. Pass an empty stale_after to clear the review date; omit it " \
                    "to leave it as is. Find overdue assets with search(stale: true)."
        annotations idempotent: false

        input_schema do
          required(:slug).filled(:string)
          optional(:stale_after).value(:string)
        end

        output_schema do
          required(:slug).filled(:string)
          required(:verified_at).filled(:string)
          required(:stale_after).maybe(:string)
        end

        def invoke(slug:, server_context:, **options)
          actor = actor_from(server_context)
          args = { actor:, slug: }
          args[:stale_after] = options[:stale_after] if options.key?(:stale_after)
          asset = ::Assets::Verify.mutate(**args)

          text = "Verified #{asset.slug} at #{asset.verified_at.iso8601}"
          text += " — re-check after #{asset.stale_after.iso8601}" if asset.stale_after
          text_response(text, data: { slug: asset.slug, verified_at: asset.verified_at.iso8601, stale_after: asset.stale_after&.iso8601 })
        end
      end
    end
  end
end
