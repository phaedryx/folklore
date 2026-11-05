module FolkloreMcp
  module Tools
    module Tasks
      class Pending < FolkloreMcp::Tool
        DEFAULT_LIMIT = 100

        tool_name "get_pending_tasks"
        description "List tasks under a path prefix, oldest first, one `slug  location` line each; a task " \
                    "waiting on dependencies ends its line with `blocked by <slugs>`. " \
                    "Lists pending tasks by default; pass status (pending, ready, in_progress, done, failed " \
                    "or all) for others: ready is pending with every dependency done; cancelled is reserved " \
                    "and nothing sets it yet. To resume after a crash, look for in_progress tasks " \
                    "first: a claim you were holding does not show as pending. Optionally filter to " \
                    "tasks having ALL of the given tags. Returns at most #{DEFAULT_LIMIT} tasks unless you " \
                    "pass limit (up to #{::Tasks::List::MAX_LIMIT}); truncated says more remain, and offset pages on."
        annotations read_only: true, idempotent: true

        input_schema do
          required(:path_prefix).filled(:string)
          optional(:tags).array(:string)
          optional(:status).filled(:string)
          optional(:limit).filled(:integer)
          optional(:offset).filled(:integer)
        end

        output_schema do
          required(:tasks).array(:hash) do
            required(:slug).filled(:string)
            required(:location).filled(:string)
            required(:name).filled(:string)
            required(:dir).filled(:string)
            required(:status).filled(:string)
            required(:claimed_by).maybe(:string)
            required(:lease_until).maybe(:string)
            required(:attempts).filled(:integer)
            required(:tags).array(:string)
            required(:created_at).filled(:string)
            required(:depends_on).array(:string)
            required(:blocked_by).array(:string)
          end
          required(:truncated).filled(:bool)
        end

        def invoke(path_prefix:, server_context:, tags: [], status: "pending", limit: nil, offset: 0)
          actor = actor_from(server_context)
          status = status.presence || "pending"
          limit ||= DEFAULT_LIMIT
          rows = ::Tasks::List.query(path_prefix:, status:, tags:, actor:, limit:, offset:).map do |asset|
            task = asset.task
            { slug: asset.slug, location: asset.location, name: asset.name, dir: asset.dir, status: task.status,
              claimed_by: Tasks.claimed_by(task), lease_until: task.lease_until&.iso8601, attempts: task.attempts,
              tags: asset.tags.map(&:name), created_at: asset.created_at.iso8601,
              depends_on: Tasks.depends_on(task), blocked_by: Tasks.blocked_by(task) }
          end

          empty = status == "all" ? "No tasks under #{path_prefix}" : "No #{status} tasks under #{path_prefix}"
          text = rows.any? ? rows.map { |row| line(row) }.join("\n") : empty
          # A full page may be the last one; look one row past it to tell.
          truncated = rows.size == limit &&
                      ::Tasks::List.query(path_prefix:, status:, tags:, actor:, limit: 1, offset: offset.to_i + limit).exists?
          text += "\n(#{limit} shown; pass offset: #{offset.to_i + limit} for more)" if truncated
          text_response(text, data: { tasks: rows, truncated: })
        end

        private

        def line(row)
          text = "#{row[:slug]}  #{row[:location]}"
          text += "  blocked by #{row[:blocked_by].join(', ')}" if row[:blocked_by].any?
          text
        end
      end
    end
  end
end
