# A tool that exists only in the test suite, so the transport and the Tool
# base class can be exercised before any domain tool lands.
module FolkloreMcpTest
  class EchoTool < FolkloreMcp::Tool
    tool_name "echo"
    description "Echo the message back, prefixed with the caller's handle and agent."
    annotations read_only: true, idempotent: true

    input_schema do
      required(:message).filled(:string)
      optional(:format).filled(:string)
      optional(:fail_with).filled(:string)
    end

    output_schema do
      required(:message).filled(:string)
      required(:actor).filled(:string)
    end

    def invoke(message:, server_context:, format: "text", fail_with: nil)
      actor = actor_from(server_context)
      case fail_with
      when "invalid" then Tag.create!(name: nil)
      when "boom" then raise "kaboom secret details"
      end

      data = { message:, actor: "#{actor.handle}/#{actor.agent}" }
      respond(format:, text: "#{data[:actor]}: #{message}", data:)
    end
  end
end
