module FolkloreMcp
  module Tools
    module Events
      class Activity < FolkloreMcp::Tool
        tool_name "activity"
        description "Recent activity across the store, newest first (50 by default). Filter by actor " \
                    "(a handle, handle/agent, or email), tag, and since/before timestamps (ISO 8601 " \
                    "or a plain date and time). Pass since_id to read forward from a cursor instead: " \
                    "events after that id, oldest first."
        # The tool's default, as before; the web page shows more.
        DEFAULT_LIMIT = 50
        annotations read_only: true, idempotent: true

        input_schema do
          optional(:actor).filled(:string)
          optional(:tag).filled(:string)
          optional(:since).filled(:string)
          optional(:before).filled(:string)
          optional(:since_id).filled(:integer)
          optional(:limit).filled(:integer)
        end

        output_schema do
          required(:events).array(:hash) do
            required(:id).filled(:integer)
            required(:created_at).filled(:string)
            required(:actor).maybe(:hash) { required(:handle).filled(:string); required(:agent).filled(:string) }
            required(:action).filled(:string)
            required(:slug).maybe(:string)
            required(:metadata).hash
          end
        end

        def invoke(server_context:, actor: nil, tag: nil, since: nil, before: nil, since_id: nil, limit: nil)
          actor_from(server_context)
          events = ::Events::List.query(actor:, tag:, since: parse_time(:since, since), before: parse_time(:before, before),
                                        since_id:, limit: limit || DEFAULT_LIMIT)
          rows = events.map do |event|
            { id: event.id, created_at: event.created_at.iso8601,
              actor: event.actor_user && { handle: event.actor_user.handle, agent: event.actor_agent.to_s },
              action: event.action, slug: event.asset&.slug, metadata: event.metadata }
          end
          lines = rows.map do |row|
            who = row[:actor] ? Actor.label(row[:actor][:handle], row[:actor][:agent]) : "?"
            "#{row[:created_at]}  #{who}  #{row[:action]}  #{row[:slug] || '—'}"
          end
          # The detail goes after the four columns, so a parser of those still works.
          lines = lines.zip(events).map { |line, event| [ line, ::Events::Detail.call(event).presence ].compact.join("  ") }

          text_response(lines.any? ? lines.join("\n") : "No activity", data: { events: rows })
        end

        private

        def parse_time(field, value)
          return nil if value.blank?

          Time.zone.iso8601(value)
        rescue ArgumentError
          parsed = Time.zone.parse(value) rescue nil
          return parsed if parsed

          raise ::Events::InvalidTimestampError, "#{field} must be an ISO 8601 timestamp, got #{value.inspect}"
        end
      end
    end
  end
end
