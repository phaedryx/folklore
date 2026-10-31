require "mcp"
require "dry/schema"

Dry::Schema.load_extensions(:json_schema)

module FolkloreMcp
  # Base class for every MCP tool. Subclasses declare `tool_name`, a
  # `description`, `input_schema` and `output_schema` blocks (dry-schema,
  # emitted as JSON Schema), and `annotations`; they implement
  # `#invoke(**args, server_context:)` and answer with `text_response` or
  # `json_response`.
  #
  # Subclasses register themselves on definition. The wire name is always
  # declared explicitly: tool classes live under their domain module, so a
  # name derived from the class name would be wrong for most of them.
  class Tool < MCP::Tool
    MissingActorError = Class.new(StandardError)
    SCOPE_ERROR = "Forbidden: token lacks write scope".freeze
    READ_SCOPE_ERROR = "Forbidden: token lacks read scope".freeze

    # How MCP shows a DomainErrors entry: "<prefix> [<code>]: <message>", the
    # prefix chosen by status. The task-queue outcomes are named for themselves.
    # ERROR_TEXT parses one back; errors not in the registry carry no code.
    STATUS_PREFIXES = {
      not_found: "Not found",
      forbidden: "Forbidden",
      conflict: "Conflict",
      unprocessable_content: "Invalid"
    }.freeze
    CODE_PREFIXES = {
      "not_a_task" => "Not a task",
      "already_claimed" => "Already claimed",
      "no_pending_task" => "No pending task",
      "wrong_claimer" => "Wrong claimer"
    }.freeze
    ERROR_TEXT = /\A(?<prefix>[^\[:]+) \[(?<code>[a-z_]+)\]: (?<message>.*)\z/m

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

      # tools/list is read into every session, so it leaves out what says
      # nothing: `$schema` (MCP's default dialect is the one we emit), hints
      # equal to the spec's defaults (destructive, not idempotent, open world;
      # destructive and idempotent mean nothing on a read-only tool), and in
      # output schemas the minLength and not-null that `filled` adds.
      def to_h
        hash = super.merge(annotations: annotation_hints)
        hash[:inputSchema] = trim_schema(hash[:inputSchema], output: false)
        hash[:outputSchema] = trim_schema(hash[:outputSchema], output: true) if hash[:outputSchema]
        hash
      end

      def prefix_for(entry)
        CODE_PREFIXES.fetch(entry.code) { STATUS_PREFIXES.fetch(entry.status) }
      end

      def error_text(error)
        entry = DomainErrors.for(error)
        "#{prefix_for(entry)} [#{entry.code}]: #{DomainErrors.message(error)}"
      end

      # Failures are text only: some clients check any structured content
      # against the outputSchema, error or not. A registered error
      # (DomainErrors) is mapped here and nowhere else; anything else is
      # "Internal error".
      def call(server_context: nil, **args)
        scope_error = scope_error(server_context)
        return failure(scope_error) if scope_error

        unknown = unknown_arguments(args)
        return failure("Invalid: unknown argument#{'s' if unknown.size > 1} #{unknown.join(', ')}") if unknown.any?

        new.invoke(**args, server_context:)
      rescue MissingActorError
        failure("Unauthenticated: no actor on request")
      rescue *DomainErrors.classes => e
        failure(error_text(e))
      rescue => e
        raise if Rails.env.test? && ENV["MCP_RAISE_ERRORS"] == "1"
        Rails.logger.error("[MCP] #{name_value} #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
        failure("Internal error")
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

      def annotation_hints
        hints = annotations_value
        return { openWorldHint: false, readOnlyHint: true } if hints.read_only_hint

        { destructiveHint: (false unless hints.destructive_hint), idempotentHint: (true if hints.idempotent_hint),
          openWorldHint: (false unless hints.open_world_hint) }.compact
      end

      def trim_schema(node, output:)
        case node
        when Hash
          node.each_with_object({}) do |(key, value), trimmed|
            next if key == :"$schema"
            next if key == :not && value == { type: "null" } && node[:type].is_a?(String)
            next if output && key == :minLength && value == 1

            trimmed[key] = trim_schema(value, output:)
          end
        when Array then node.map { |child| trim_schema(child, output:) }
        else node
        end
      end

      def failure(text)
        MCP::Tool::Response.new([ { type: "text", text: } ], error: true)
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
    # a query, `read` marks one followed). It is telemetry: a
    # failure is logged and never fails the call.
    def telemetry
      yield
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[MCP] #{self.class.name_value} search log failed: #{e.class}: #{e.message}")
    end

    # A summary as text, with the data as structured content when there is any.
    def text_response(text, data: nil)
      MCP::Tool::Response.new([ { type: "text", text: text.to_s } ], structured_content: data)
    end

    # The data as structured content and, serialized, as the text.
    def json_response(data)
      MCP::Tool::Response.new([ { type: "text", text: JSON.generate(data) } ], structured_content: data)
    end
  end
end
