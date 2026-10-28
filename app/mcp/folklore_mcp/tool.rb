require "mcp"
require "dry/schema"

Dry::Schema.load_extensions(:json_schema)

module FolkloreMcp
  # Base class for every MCP tool. Subclasses declare `tool_name`, a
  # `description`, `input_schema` and `output_schema` blocks (dry-schema,
  # emitted as JSON Schema), and `annotations`; they implement
  # `#invoke(**args, server_context:)` and answer with `respond`,
  # `text_response`, `json_response` or `error_response`.
  #
  # Subclasses register themselves on definition. The wire name is always
  # declared explicitly: tool classes live under their domain module, so a
  # name derived from the class name would be wrong for most of them.
  class Tool < MCP::Tool
    MissingActorError = Class.new(StandardError)
    SCOPE_ERROR = "Forbidden: token lacks write scope".freeze
    READ_SCOPE_ERROR = "Forbidden: token lacks read scope".freeze

    # Errors a caller can act on, with the prefix their message gets. Domain
    # modules add their own with `FolkloreMcp::Tool.user_error(klass, prefix)`.
    USER_ERRORS = {
      Asset::InvalidNameError => "Invalid",
      Asset::InvalidDirError => "Invalid",
      Asset::InvalidStaleAfterError => "Invalid",
      Actor::InvalidAgentError => "Invalid",
      Checkpoint::NoHandleError => "Invalid",
      ActiveRecord::RecordNotFound => "Not found",
      ActiveRecord::StaleObjectError => "Conflict"
    }

    class << self
      def inherited(subclass)
        super
        Tool.register(subclass)
      end

      def register(tool)
        registered_tools << tool unless registered_tools.include?(tool)
      end

      def registered_tools
        @registered_tools ||= []
      end

      # Closed: an argument the schema does not name is refused by the gem as
      # `Invalid arguments: ...` before the tool runs.
      def input_schema(value = NOT_SET, &block)
        return super(value) unless block

        super(json_schema_from(block).merge(additionalProperties: false))
      end

      def output_schema(value = NOT_SET, &block)
        return super(value) unless block

        super(json_schema_from(block))
      end

      # Defaults describe a plain write: not destructive, not idempotent, no
      # interaction with the outside world.
      def annotations(**hints)
        return annotations_value if hints.empty?

        @annotations_value = MCP::Tool::Annotations.new(
          read_only_hint: hints.fetch(:read_only, false),
          destructive_hint: hints.fetch(:destructive, false),
          idempotent_hint: hints.fetch(:idempotent, false),
          open_world_hint: hints.fetch(:open_world, false)
        )
      end

      def annotations_value
        @annotations_value ||= annotations(read_only: false)
      end

      def to_h
        super.merge(annotations: annotations_value.to_h)
      end

      def user_error(klass, prefix)
        USER_ERRORS[klass] = prefix
      end

      # Failures answer in the format the caller asked for: a tool that takes
      # `format: "json"` gets `{"error": "..."}` back, as its successes are JSON.
      def call(server_context: nil, **args)
        format = args[:format]
        scope_error = scope_error(server_context)
        return failure(scope_error, format:) if scope_error

        unknown = unknown_arguments(args)
        return failure("Invalid: unknown argument#{'s' if unknown.size > 1} #{unknown.join(', ')}", format:) if unknown.any?

        new.invoke(**args, server_context:)
      rescue MissingActorError
        failure("Unauthenticated: no actor on request", format:)
      rescue ActiveRecord::RecordInvalid => e
        failure("Invalid: #{e.record.errors.full_messages.join(', ')}", format:)
      rescue *USER_ERRORS.keys => e
        failure("#{USER_ERRORS.fetch(e.class) { USER_ERRORS.find { |k, _| e.is_a?(k) }.last }}: #{e.message}", format:)
      rescue => e
        raise if Rails.env.test? && ENV["MCP_RAISE_ERRORS"] == "1"
        Rails.logger.error("[MCP] #{name_value} #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
        failure("Internal error", format:)
      end

      private

      # Checked before the tool runs, so a refused call has no side effects.
      # A read-only tool needs the read scope and any other the write scope.
      # Web sessions carry no token and are not scope-checked.
      def scope_error(server_context)
        token = server_context && (server_context[:actor] || server_context["actor"])&.token
        return if token.nil?

        if annotations_value.read_only_hint
          READ_SCOPE_ERROR unless token.readable?
        else
          SCOPE_ERROR unless token.writable?
        end
      end

      # The transport already refuses these against the closed schema; this
      # covers callers that reach `call` directly, so an unknown keyword is
      # never an ArgumentError reported as "Internal error".
      def unknown_arguments(args)
        properties = input_schema_value&.to_h&.dig(:properties)
        return [] unless properties

        args.keys.map(&:to_s) - properties.keys.map(&:to_s)
      end

      def failure(text, format: nil)
        return MCP::Tool::Response.new([ { type: "text", text: } ], error: true) unless format.to_s == "json"

        payload = { error: text }
        MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ], structured_content: payload, error: true)
      end

      def json_schema_from(block)
        json = Dry::Schema.JSON(&block).json_schema(loose: true)
        json.delete(:$schema)
        json.delete(:required) if json[:required].is_a?(Array) && json[:required].empty?
        json
      end
    end

    # The request's actor, or the same token acting as `agent` when the tool
    # takes an agent override. The override is a label within the token's
    # user; a web session has no token to relabel.
    def actor_from(server_context, agent: nil)
      actor = server_context && (server_context[:actor] || server_context["actor"])
      raise MissingActorError, "no actor in server_context" unless actor
      return actor if agent.to_s.strip.empty?
      raise Actor::InvalidAgentError, "agent override needs a token; web sessions act as #{Actor::WEB_AGENT}" unless actor.token

      Actor.for_token(actor.token, agent:)
    end

    # Marks a recent search as answered by this read (see SearchLogs::Follow).
    def follow_search(actor, asset)
      telemetry { SearchLogs::Follow.mutate(actor:, slug: asset.slug) }
    end

    # The search log is the only thing read-only tools write (`search` records
    # a query, `read` and `read_path` mark one followed). It is telemetry: a
    # failure is logged and never fails the call.
    def telemetry
      yield
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[MCP] #{self.class.name_value} search log failed: #{e.class}: #{e.message}")
    end

    def text_response(text, data: nil)
      respond(format: "text", text:, data:)
    end

    def json_response(data)
      respond(format: "json", text: data, data:)
    end

    def error_response(message, format: "text")
      if format.to_s == "json"
        respond(format:, text: { error: message.to_s }, error: true)
      else
        respond(format:, text: message.to_s, error: true)
      end
    end

    # Text content always; structured content whenever there is data for it.
    def respond(format:, text:, data: nil, error: false)
      if format.to_s == "json"
        payload = data || text
        json = payload.is_a?(String) ? payload : JSON.generate(payload)
        structured = payload.is_a?(String) ? JSON.parse(json) : payload
        MCP::Tool::Response.new([ { type: "text", text: json } ], structured_content: structured, error:)
      else
        MCP::Tool::Response.new([ { type: "text", text: text.to_s } ], structured_content: data, error:)
      end
    end
  end
end
