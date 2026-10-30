module FolkloreMcp
  module Tools
    module Assets
      class Read < FolkloreMcp::Tool
        tool_name "read"
        description "Read by ref: a slug, a location (handle/dir/name), or an array of up to 50 of either. " \
                    "Returns the whole asset, or with include just the slug and those fields. An array " \
                    "returns {assets, bytes_returned, truncated}: a ref that fails gets error and code in " \
                    "its place, and content stops after max_bytes (default 100000, at most 1000000). " \
                    "Archived assets are not found."
        annotations read_only: true, idempotent: true

        input_schema(
          type: "object",
          properties: {
            ref: { anyOf: [ { type: "string", minLength: 1 }, { type: "array", items: { type: "string", minLength: 1 } } ] },
            include: { type: "array", items: { type: "string", enum: ReadFormatter::FIELDS } },
            max_bytes: { type: "integer" }
          },
          required: %w[ref],
          additionalProperties: false
        )

        # One asset for a ref, a list of them for an array. The asset's fields
        # are defined once and referenced twice.
        output_schema(
          type: "object",
          "$defs": {
            asset: json_schema_from(proc do
              instance_exec(&ASSET_FIELDS)
              optional(:ref).filled(:string)
              optional(:error).filled(:string)
              optional(:code).filled(:string)
              optional(:content_omitted).filled(:bool)
            end)
          },
          "$ref": "#/$defs/asset",
          properties: {
            assets: { type: "array", items: { "$ref": "#/$defs/asset" } },
            bytes_returned: { type: "integer" },
            truncated: { type: "boolean" }
          }
        )

        def invoke(ref:, server_context:, include: nil, max_bytes: nil)
          actor = actor_from(server_context)
          validate_include!(include)
          return read_many(ref, include:, max_bytes:, actor:) if ref.is_a?(Array)
          raise ::Assets::BulkRead::InvalidArgumentError, "max_bytes applies only to an array of refs" if max_bytes

          asset = ::Assets::BulkRead.read_one(ref, actor:)
          follow_search(actor, asset)
          json_response(ReadFormatter.call(asset, include:))
        end

        private

        # Callers that reach `call` directly skip the transport's schema check.
        def validate_include!(include)
          unknown = Array(include) - ReadFormatter::FIELDS
          raise ::Assets::BulkRead::InvalidArgumentError, "unknown include #{unknown.join(', ')}" if unknown.any?
        end

        def read_many(refs, include:, max_bytes:, actor:)
          include_content = include.nil? || include.include?("content")
          result = ::Assets::BulkRead.query(refs:, max_bytes:, include_content:, actor:)
          ::Assets::Serializer.preload(result.items.filter_map(&:asset))

          json_response(assets: result.items.map { |item| entry(item, include:) },
                        bytes_returned: result.bytes_returned, truncated: result.truncated)
        end

        def entry(item, include:)
          if item.error
            failure = DomainErrors.for(item.error)
            return { ref: item.ref, error: "#{Tool.prefix_for(failure)}: #{DomainErrors.message(item.error)}", code: failure.code }
          end

          data = ReadFormatter.call(item.asset, include:)
          item.content_omitted ? data.except(:content).merge(content_omitted: true) : data
        end
      end
    end
  end
end
