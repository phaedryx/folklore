module FolkloreMcp
  module Tools
    module Assets
      class List < FolkloreMcp::Tool
        tool_name "list"
        description "List live assets under a path (the directory and its whole subtree), one " \
                    "`slug  location` line each. Optionally filter to assets having ALL of the " \
                    "given tags; sort by name (default), created_at or updated_at. Returns 100 " \
                    "(at most 500) from offset, and next_offset when there are more."
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
          optional(:next_offset).filled(:integer)
        end

        def invoke(path:, server_context:, tags: [], sort: nil, limit: nil, offset: 0)
          actor = actor_from(server_context)
          limit = (limit || ::Assets::List::DEFAULT_LIMIT).to_i.clamp(1, ::Assets::List::MAX_LIMIT)
          # One row past the page says whether there is another.
          assets = ::Assets::List.query(path:, tags:, sort:, offset:, actor:).limit(limit + 1).to_a
          more = assets.size > limit
          rows = assets.first(limit).map do |asset|
            { slug: asset.slug, location: asset.location, name: asset.name, dir: asset.dir,
              tags: asset.tags.map(&:name), status: asset.status, updated_at: asset.updated_at.iso8601 }
          end
          lines = rows.map { |row| "#{row[:slug]}  #{row[:location]}" }
          data = { assets: rows }
          data[:next_offset] = offset.to_i + limit if more
          lines << "(more: offset #{data[:next_offset]})" if more

          text_response(lines.any? ? lines.join("\n") : "No assets under #{path}", data:)
        end
      end
    end
  end
end
