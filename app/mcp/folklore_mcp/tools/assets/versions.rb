module FolkloreMcp
  module Tools
    module Assets
      class Versions < FolkloreMcp::Tool
        tool_name "versions"
        description "List prior versions of an asset by slug, newest first, with who wrote each. " \
                    "Pass id for that one version's content; restore(slug, version: id) puts it back."
        annotations read_only: true, idempotent: true

        input_schema do
          required(:slug).filled(:string)
          optional(:id).filled(:integer)
        end

        output_schema do
          required(:versions).array(:hash) do
            required(:id).filled(:integer)
            required(:created_at).filled(:string)
            required(:content_type).maybe(:string)
            required(:actor).maybe(:hash) { required(:handle).filled(:string); required(:agent).filled(:string) }
            optional(:content).maybe(:string)
          end
        end

        def invoke(slug:, server_context:, id: nil)
          actor = actor_from(server_context)
          if id
            version = ::Versions::Read.query(slug:, id:, actor:)
            return json_response(versions: [ row(version).merge(content: version.content) ])
          end

          rows = ::Versions::List.query(slug:, actor:).map { |version| row(version) }
          lines = rows.map do |row|
            by = row[:actor] ? Actor.label(row[:actor][:handle], row[:actor][:agent]) : "?"
            "- #{row[:id]}  #{row[:created_at]}  by #{by}  (#{row[:content_type]})"
          end

          text_response(lines.any? ? lines.join("\n") : "No prior versions", data: { versions: rows })
        end

        private

        def row(version)
          { id: version.id, created_at: version.created_at.iso8601, content_type: version.content_type,
            actor: version.actor_user && { handle: version.actor_user.handle, agent: version.actor_agent.to_s } }
        end
      end
    end
  end
end
