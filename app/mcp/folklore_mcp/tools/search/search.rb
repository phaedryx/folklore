module FolkloreMcp
  module Tools
    module Search
      class Search < FolkloreMcp::Tool
        tool_name "search"

        DEFAULT_LIMIT = 50
        SNIPPET_WINDOW = 120
        # One fragment around the query words, unmarked, so the line reads as prose.
        HEADLINE_OPTIONS = %q(MaxFragments=1, MaxWords=24, MinWords=12, StartSel="", StopSel="").freeze
        ANY_TERM = ::Assets::Search::ANY_TERM
        # Filters at their default are not logged; `stale: false` is a real filter and stays.
        FILTER_DEFAULTS = { within: nil, tags: [], status: nil, task_status: nil, stale: nil, exclude_tags: [],
                            sort: nil, limit: nil, offset: 0, include_versions: false }.freeze

        description "Full-text + fuzzy-name search across live assets, optionally scoped to a path prefix and tag set. " \
                    "Filter by status (a note's open|done or a task's pending|in_progress|done|failed), by " \
                    "task_status (tasks only), or exclude " \
                    "assets having ANY of exclude_tags (e.g. tagged X but not done). " \
                    "Pass stale: true for assets whose stale_after review date has passed (false for the rest; " \
                    "assets with no review date are never stale). q is required except with stale: true, where " \
                    "leaving it out lists every overdue asset, most overdue first. " \
                    "Optionally sort (name|created_at|updated_at) and paginate (limit/offset). " \
                    "Each result is a `slug  name  (dir)` line with a short content snippet around the first match " \
                    "beneath it. Pass include_versions: true to also match content an asset used to have but no " \
                    "longer does, for finding something you wrote and later edited away. Those hits are snippeted " \
                    "from the version and marked with the date it was displaced."

        annotations read_only: true, idempotent: true

        input_schema do
          optional(:q).filled(:string)
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
          required(:query).maybe(:string)
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

        def invoke(q: nil, within: nil, tags: [], status: nil, task_status: nil, stale: nil, exclude_tags: [], sort: nil,
                   limit: nil, offset: 0, include_versions: false, server_context:)
          actor = actor_from(server_context)
          if q.blank? && stale != true
            raise ::Assets::Search::InvalidArgumentError, "q is required unless stale is true"
          end

          filters = { within:, tags:, status:, task_status:, stale:, exclude_tags:, sort:, limit:, offset:,
                      include_versions: }.reject { |key, value| value == FILTER_DEFAULTS[key] || (value.blank? && value != false) }
          results = ::Assets::Search.query(
            query: q, path: within, tags:, status:, task_status:, stale:, exclude_tags:,
            sort:, limit:, offset:, include_versions:, actor:
          )
          results = results.limit(DEFAULT_LIMIT) if limit.blank?
          entries = entries_for(results.to_a, q, include_versions)

          telemetry { SearchLogs::Record.mutate(actor:, query: q, filters:, result_slugs: entries.map { |e| e[:slug] }) }

          text = entries.map { |e| line_for(e) }.join("\n")
          empty = q.blank? ? "No overdue assets" : "No results for #{q.inspect}"
          text_response(entries.any? ? text : empty,
                        data: { query: q, count: entries.size, results: entries })
        end

        private

        # Which content a snippet comes from is decided the way the match was: by the
        # database, on stems. A substring check in Ruby would miss "databases" against
        # "database" and fall through to an old version, calling a live result edited.
        def entries_for(assets, query, include_versions)
          ids = assets.map(&:id)
          current = current_headlines(ids, query)
          displaced = include_versions ? version_headlines(ids - current.keys, query) : {}

          assets.map do |asset|
            snippet, displaced_at =
              if current.key?(asset.id) then [ current[asset.id], nil ]
              elsif displaced.key?(asset.id) then displaced[asset.id]
              else [ head_of(asset.content), nil ]
              end
            { slug: asset.slug, name: asset.name, dir: asset.dir, location: asset.location, snippet:, displaced_at: }
          end
        end

        # Snippets for the assets whose current content mentions any query term, keyed by id.
        def current_headlines(ids, query)
          Asset.where(id: ids)
               .where("assets.content_tsv @@ #{ANY_TERM}", query)
               .pluck(:id, Arel.sql(Asset.sanitize_sql_array([
                 "ts_headline('english', coalesce(assets.content, ''), #{ANY_TERM}, ?)", query, HEADLINE_OPTIONS
               ])))
               .to_h { |id, text| [ id, squish(text) ] }
        end

        # An asset can match only through content it no longer has, in which case snippeting
        # its current body shows the searcher something that has nothing to do with the query.
        # The most recent matching version is the one that was edited away last.
        def version_headlines(ids, query)
          return {} if ids.empty?

          Version.where(asset_id: ids)
                 .where("versions.content_tsv @@ #{ANY_TERM}", query)
                 .select(Version.sanitize_sql_array([
                   "DISTINCT ON (versions.asset_id) versions.asset_id, versions.created_at, " \
                   "ts_headline('english', coalesce(versions.content, ''), #{ANY_TERM}, ?) AS headline",
                   query, HEADLINE_OPTIONS
                 ]))
                 .order("versions.asset_id, versions.created_at DESC")
                 .to_h { |v| [ v.asset_id, [ squish(v.headline), v.created_at.to_date.iso8601 ] ] }
        end

        # A name-only match has nothing in its body to point at; the opening is the context.
        def head_of(content)
          text = squish(content)
          text.length > SNIPPET_WINDOW ? "#{text[0, SNIPPET_WINDOW]}…" : text
        end

        def squish(text)
          text.to_s.gsub(/\s+/, " ").strip
        end

        def line_for(entry)
          snippet = entry[:displaced_at] ? "(edited #{entry[:displaced_at]}) #{entry[:snippet]}" : entry[:snippet]
          "#{entry[:slug]}  #{entry[:name]}  (#{entry[:dir]})\n    #{snippet}"
        end
      end
    end
  end
end
