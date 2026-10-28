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

      def input_schema(value = NOT_SET, &block)
        return super(value) unless block

        super(json_schema_from(block))
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

      def call(server_context: nil, **args)
        new.invoke(**args, server_context:)
      rescue MissingActorError
        failure("Unauthenticated: no actor on request")
      rescue ActiveRecord::RecordInvalid => e
        failure("Invalid: #{e.record.errors.full_messages.join(', ')}")
      rescue *USER_ERRORS.keys => e
        failure("#{USER_ERRORS.fetch(e.class) { USER_ERRORS.find { |k, _| e.is_a?(k) }.last }}: #{e.message}")
      rescue => e
        raise if Rails.env.test? && ENV["MCP_RAISE_ERRORS"] == "1"
        Rails.logger.error("[MCP] #{name_value} #{e.class}: #{e.message}\n#{e.backtrace&.first(8)&.join("\n")}")
        failure("Internal error")
      end

      private

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
