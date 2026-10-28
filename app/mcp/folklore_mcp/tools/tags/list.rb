module FolkloreMcp
  module Tools
    module Tags
      class List < FolkloreMcp::Tool
        tool_name "tags"
        description "Enumerate the tags applied to live assets with a count of live assets per tag, " \
                    "sorted by count desc then name asc. Optionally scope to a path prefix with `within`."
        annotations read_only: true, idempotent: true

        input_schema do
          optional(:within).filled(:string)
        end

        output_schema do
          required(:tags).array(:hash) do
            required(:name).filled(:string)
            required(:count).filled(:integer)
          end
        end

        def invoke(server_context:, within: nil)
          actor_from(server_context)
          counts = ::Tags::List.query(within:)
          data = { tags: counts.map { |name, count| { name:, count: } } }

          text_response(counts.any? ? counts.map { |name, count| "#{name}  #{count}" }.join("\n") : "No tags", data:)
        end
      end
    end
  end
end
