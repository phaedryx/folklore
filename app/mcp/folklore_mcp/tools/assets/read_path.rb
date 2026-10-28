module FolkloreMcp
  module Tools
    module Assets
      class ReadPath < FolkloreMcp::Tool
        tool_name "read_path"
        description <<~DESC.strip
          Read an asset by location instead of slug. Provide either location (full path
          including filename, e.g. "member/notes/plan.md") or path + name (directory + leaf).
          Pass format: "json" for structured output. Optionally pass with: an array of fields
          to return (content, name, path, content_type, status, owner, tags, created_at,
          updated_at, backlinks, created_by, updated_by, verified_by, version) — omit with for
          raw content (text) or the full asset (json). Returns Not found for unknown or
          archived assets.
        DESC
        annotations read_only: true, idempotent: true

        input_schema do
          optional(:location).filled(:string)
          optional(:path).filled(:string)
          optional(:name).filled(:string)
          optional(:format).filled(:string)
          optional(:with).array(:string)
        end

        output_schema(&ASSET_FIELDS)

        def invoke(server_context:, format: "text", location: nil, path: nil, name: nil, with: nil)
          actor = actor_from(server_context)
          asset = ::Assets::ReadByPath.query(location:, path:, name:, actor:)
          requested = Array(with).map(&:to_sym) & READ_FIELDS

          rendered = ReadFormatter.render(asset, requested:)
          respond(format:, text: rendered.text, data: rendered.data)
        end
      end
    end
  end
end
