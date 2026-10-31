# A tool that exists only in the test suite, so the transport and the Tool
# base class can be exercised without a domain tool. Defining it registers it
# like any tool, so it is unregistered at once and served only to tests that
# include ServesEchoTool; every other test sees the real tools/list.
module FolkloreMcpTest
  class EchoTool < FolkloreMcp::Tool
    tool_name "echo"
    description "Echo the message back, prefixed with the caller's handle and agent."
    annotations read_only: true, idempotent: true

    input_schema do
      required(:message).filled(:string)
      optional(:json).filled(:bool)
      optional(:fail_with).filled(:string)
    end

    output_schema do
      required(:message).filled(:string)
      required(:actor).filled(:string)
    end

    def invoke(message:, server_context:, json: false, fail_with: nil)
      actor = actor_from(server_context)
      case fail_with
      when "invalid" then Tag.create!(name: nil)
      when "boom" then raise "kaboom secret details"
      when "dir" then Asset.validate_dir!("member/../x")
      when "stale" then Asset.parse_stale_after!("soon")
      when "agent" then Actor.for_token(actor.token, agent: "Bad Agent")
      when "missing" then Asset.find_by!(slug: "00000000")
      when "conflict" then raise ActiveRecord::StaleObjectError.new(Asset.new, "update")
      end

      data = { message:, actor: "#{actor.handle}/#{actor.agent}" }
      json ? json_response(data) : text_response("#{data[:actor]}: #{message}", data:)
    end
  end

  FolkloreMcp::Tool.registered_tools.delete(EchoTool)

  module ServesEchoTool
    extend ActiveSupport::Concern

    included do
      setup { FolkloreMcp::Tool.register(EchoTool) }
      teardown { FolkloreMcp::Tool.registered_tools.delete(EchoTool) }
    end
  end
end
