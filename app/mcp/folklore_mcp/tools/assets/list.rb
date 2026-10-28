module FolkloreMcp
  module Tools
    module Assets
      class List < FolkloreMcp::Tool
        tool_name "list"
        description "List live assets under a path (the directory and its whole subtree), one " \
                    "`slug  location` line each. Optionally filter to assets having ALL of the " \
                    "given tags; sort by name (default), created_at or updated_at; page with " \
                    "limit and offset."
        annotations read_only: true, idempotent: true

        input_schema do
          required(:path).filled(:string)
          optional(:tags).array(:string)
          optional(:sort).filled(:string)
          optional(:limit).filled(:integer)
          optional(:offset).filled(:integer)
        end

        output_schema do
          required(:assets).array(:hash) do
            required(:slug).filled(:string)
            required(:location).filled(:string)
            required(:name).filled(:string)
            required(:dir).filled(:string)
            required(:tags).array(:string)
            required(:status).maybe(:string)
            required(:updated_at).filled(:string)
          end
        end

        def invoke(path:, server_context:, tags: [], sort: nil, limit: nil, offset: 0)
          actor = actor_from(server_context)
          rows = ::Assets::List.query(path:, tags:, sort:, limit:, offset:, actor:).map do |asset|
            { slug: asset.slug, location: asset.location, name: asset.name, dir: asset.dir,
              tags: asset.tags.map(&:name), status: asset.status, updated_at: asset.updated_at.iso8601 }
          end
          lines = rows.map { |row| "#{row[:slug]}  #{row[:location]}" }

          text_response(lines.any? ? lines.join("\n") : "No assets under #{path}", data: { assets: rows })
        end
      end
    end
  end
end
