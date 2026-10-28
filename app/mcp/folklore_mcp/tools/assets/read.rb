module FolkloreMcp
  module Tools
    module Assets
      class Read < FolkloreMcp::Tool
        tool_name "read"
        description <<~DESC.strip
          Read an asset by slug. With no flags it returns the raw content (default).
          Request metadata fields individually with boolean flags — any combination of
          name, path, content_type, status, owner, tags, created_at, updated_at, backlinks,
          created_by, updated_by, verified_by, version — and only those fields are returned.
          Add content: true to include the body alongside the requested metadata. Pass
          format: "json" for structured output (full asset when no flags; selected fields
          when flags are set). Returns Not found for unknown or archived assets.
        DESC
        annotations read_only: true, idempotent: true

        input_schema do
          required(:slug).filled(:string)
          optional(:format).filled(:string)
          READ_FIELDS.each { |field| optional(field).filled(:bool) }
        end

        output_schema(&ASSET_FIELDS)

        def invoke(slug:, server_context:, format: "text", **flags)
          actor = actor_from(server_context)
          asset = ::Assets::Read.query(slug:, actor:)
          requested = READ_FIELDS.select { |field| flags[field] }

          respond(format:,
                  text: ReadFormatter.call(asset, requested:, format: "text"),
                  data: ReadFormatter.call(asset, requested:, format: "json"))
        end
      end
    end
  end
end
