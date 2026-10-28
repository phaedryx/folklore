module FolkloreMcp
  module Tools
    module Assets
      class Versions < FolkloreMcp::Tool
        tool_name "versions"
        description "List prior versions of an asset by slug, newest first, with who wrote each."
        annotations read_only: true, idempotent: true

        input_schema do
          required(:slug).filled(:string)
        end

        output_schema do
          required(:versions).array(:hash) do
            required(:id).filled(:integer)
            required(:created_at).filled(:string)
            required(:content_type).maybe(:string)
            required(:actor).maybe(:hash) { required(:handle).filled(:string); required(:agent).filled(:string) }
          end
        end

        def invoke(slug:, server_context:)
          actor = actor_from(server_context)
          rows = ::Versions::List.query(slug:, actor:).map do |version|
            { id: version.id, created_at: version.created_at.iso8601, content_type: version.content_type,
              actor: version.actor_user && { handle: version.actor_user.handle, agent: version.actor_agent.to_s } }
          end
          lines = rows.map do |row|
            by = row[:actor] ? "#{row[:actor][:handle]}/#{row[:actor][:agent]}" : "?"
            "- #{row[:created_at]}  by #{by}  (#{row[:content_type]})"
          end

          text_response(lines.any? ? lines.join("\n") : "No prior versions", data: { versions: rows })
        end
      end
    end
  end
end
