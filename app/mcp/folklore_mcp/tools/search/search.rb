module FolkloreMcp
  module Tools
    module Search
      class Search < FolkloreMcp::Tool
        tool_name "search"

        DEFAULT_LIMIT = 50
        SNIPPET_WINDOW = 120
        # Filters at their default are not logged; `stale: false` is a real filter and stays.
        FILTER_DEFAULTS = { within: nil, tags: [], status: nil, task_status: nil, stale: nil, exclude_tags: [],
                            sort: nil, limit: nil, offset: 0, include_versions: false }.freeze

        description "Full-text + fuzzy-name search across live assets, optionally scoped to a path prefix and tag set. " \
                    "Filter by note status, by task_status (pending|in_progress|done|failed|cancelled), or exclude " \
                    "assets having ANY of exclude_tags (e.g. tagged X but not done). " \
                    "Pass stale: true for assets whose stale_after review date has passed (false for the rest; " \
                    "assets with no review date are never stale). " \
                    "Optionally sort (name|created_at|updated_at) and paginate (limit/offset). " \
                    "Each result is a `slug  name  (dir)` line with a short content snippet around the first match " \
                    "beneath it. Pass include_versions: true to also match content an asset used to have but no " \
                    "longer does, for finding something you wrote and later edited away. Those hits are snippeted " \
                    "from the version and marked with the date it was displaced."

        annotations read_only: true, idempotent: true

        input_schema do
          required(:q).filled(:string)
          optional(:within).filled(:string)
          optional(:tags).array(:string)
          optional(:status).filled(:string)
          optional(:task_status).filled(:string)
          optional(:stale).filled(:bool)
          optional(:exclude_tags).array(:string)
          optional(:sort).filled(:string)
          optional(:limit).filled(:integer)
          optional(:offset).filled(:integer)
          optional(:include_versions).filled(:bool)
        end

        output_schema do
          required(:query).filled(:string)
          required(:count).filled(:integer)
          required(:results).array(:hash) do
            required(:slug).filled(:string)
            required(:name).filled(:string)
            required(:dir).filled(:string)
            required(:location).filled(:string)
            required(:snippet).value(:string)
            optional(:displaced_at).maybe(:string)
          end
        end

        def invoke(q:, within: nil, tags: [], status: nil, task_status: nil, stale: nil, exclude_tags: [], sort: nil,
                   limit: nil, offset: 0, include_versions: false, server_context:)
          actor = actor_from(server_context)
          filters = { within:, tags:, status:, task_status:, stale:, exclude_tags:, sort:, limit:, offset:,
                      include_versions: }.reject { |key, value| value == FILTER_DEFAULTS[key] || (value.blank? && value != false) }
          results = Assets::Search.query(
            query: q, path: within, tags:, status:, task_status:, stale:, exclude_tags:,
            sort:, limit:, offset:, include_versions:, actor:
          )
          results = results.limit(DEFAULT_LIMIT) if limit.blank?
          entries = results.includes(:owner).map { |asset| entry_for(asset, q, include_versions) }

          SearchLogs::Record.mutate(actor:, query: q, filters:, result_slugs: entries.map { |e| e[:slug] })

          text = entries.map { |e| line_for(e) }.join("\n")
          text_response(entries.any? ? text : "No results for #{q.inspect}",
                        data: { query: q, count: entries.size, results: entries })
        end

        private

        def entry_for(asset, query, include_versions)
          snippet, displaced_at = best_snippet(asset, query, include_versions)
          { slug: asset.slug, name: asset.name, dir: asset.dir, location: asset.location, snippet:, displaced_at: }
        end

        def line_for(entry)
          snippet = entry[:displaced_at] ? "(edited #{entry[:displaced_at]}) #{entry[:snippet]}" : entry[:snippet]
          "#{entry[:slug]}  #{entry[:name]}  (#{entry[:dir]})\n    #{snippet}"
        end

        # An asset can match only through content it no longer has, in which case snippeting
        # its current body shows the searcher something that has nothing to do with the query.
        def best_snippet(asset, query, include_versions)
          return [ snippet_for(asset.content, query), nil ] if !include_versions || matches?(asset.content, query)

          version = asset.versions.order(created_at: :desc).find { |v| matches?(v.content, query) }
          return [ snippet_for(asset.content, query), nil ] unless version

          [ snippet_for(version.content, query), version.created_at.to_date.iso8601 ]
        end

        def matches?(content, query)
          content.to_s.downcase.include?(query.to_s.downcase)
        end

        def snippet_for(content, query)
          text = content.to_s.gsub(/\s+/, " ").strip
          return "" if text.empty?

          index = text.downcase.index(query.to_s.downcase)
          start = index ? [ index - 20, 0 ].max : 0
          window = text[start, SNIPPET_WINDOW].to_s

          leading = start.positive? ? "…" : ""
          trailing = (start + window.length) < text.length ? "…" : ""
          "#{leading}#{window}#{trailing}"
        end
      end
    end
  end
end
