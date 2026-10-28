module FolkloreMcp
  module Tools
    module Assets
      class BulkRead < FolkloreMcp::Tool
        tool_name "bulk_read"
        description <<~DESC.strip
          Read many assets in one call by slug and/or location (full path including filename).
          Provide at least one of slugs: or locations:. Pass format: "json" for structured output
          (default text). Set include_content: false to return metadata only. Stops including
          bodies once max_bytes is exceeded and sets truncated: true.
        DESC
        annotations read_only: true, idempotent: true

        input_schema do
          optional(:slugs).array(:string)
          optional(:locations).array(:string)
          optional(:format).filled(:string)
          optional(:include_content).filled(:bool)
          optional(:max_bytes).filled(:integer)
        end

        output_schema do
          required(:assets).array(:hash) do
            optional(:key).filled(:string)
            optional(:error).filled(:string)
            optional(:content_omitted).filled(:bool)
            instance_exec(&ASSET_FIELDS)
          end
          required(:bytes_returned).filled(:integer)
          required(:truncated).filled(:bool)
        end

        def invoke(server_context:, slugs: [], locations: [], format: "text",
                   include_content: true, max_bytes: ::Assets::BulkRead::DEFAULT_MAX_BYTES)
          actor = actor_from(server_context)
          return error_response("Provide at least one slug or location") if Array(slugs).empty? && Array(locations).empty?

          result = ::Assets::BulkRead.query(slugs:, locations:, max_bytes:, include_content:, actor:)
          AssetSerializer.preload(result.items.filter_map(&:asset))
          entries = result.items.map { |item| serialize(item, include_content:) }
          data = { assets: entries, bytes_returned: result.bytes_returned, truncated: result.truncated }

          respond(format:, text: entries.map { |entry| text_line(entry) }.join("\n\n"), data:)
        end

        private

        def serialize(item, include_content:)
          return { key: item.key, error: item.error } if item.error

          data = AssetSerializer.call(item.asset)
          data = data.except(:content) if !include_content || item.content_omitted
          data[:content_omitted] = true if item.content_omitted
          data
        end

        def text_line(entry)
          return "#{entry[:key]}: error #{entry[:error]}" if entry[:error]

          header = "#{entry[:slug]}  #{entry[:location]}"
          if entry[:content_omitted]
            "#{header}  (content omitted — byte budget exceeded)"
          elsif entry.key?(:content)
            "#{header}\n---\n#{entry[:content]}"
          else
            header
          end
        end
      end
    end
  end
end
