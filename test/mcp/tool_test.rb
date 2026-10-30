require "test_helper"

class FolkloreMcp::ToolTest < ActiveSupport::TestCase
  Echo = FolkloreMcpTest::EchoTool

  test "a tool registers itself when defined" do
    assert_includes FolkloreMcp::Tool.registered_tools, Echo
  end

  test "the wire name is declared explicitly, not derived from the class name" do
    assert_equal "echo", Echo.name_value
  end

  test "to_h exposes name, description, input schema, output schema and annotations" do
    h = Echo.to_h

    assert_equal "echo", h[:name]
    assert_kind_of String, h[:description]
    assert_equal "object", h[:inputSchema][:type]
    assert_includes h[:inputSchema][:required], "message"
    assert_equal "string", h.dig(:inputSchema, :properties, :message, :type)
    assert_equal %w[message actor], h[:outputSchema][:required]
    assert_equal({ openWorldHint: false, readOnlyHint: true }, h[:annotations])
  end

  # tools/list is read on every session, so it carries only what differs
  # from the spec's defaults (destructive, not idempotent, open world).
  test "annotations default to a non-destructive, non-idempotent, closed-world write, sent as hints off the spec's defaults" do
    klass = Class.new(FolkloreMcp::Tool) { tool_name "scratch" }
    idempotent = Class.new(FolkloreMcp::Tool) { tool_name "scratch2"; annotations destructive: true, idempotent: true }

    assert_equal({ destructiveHint: false, openWorldHint: false }, klass.to_h[:annotations])
    assert_equal({ idempotentHint: true, openWorldHint: false }, idempotent.to_h[:annotations])
    refute klass.annotations_value.read_only_hint
  ensure
    FolkloreMcp::Tool.registered_tools.delete(idempotent)
    FolkloreMcp::Tool.registered_tools.delete(klass)
  end

  test "schemas leave out what costs tokens and says nothing: $schema, and in output schemas minLength and not-null" do
    h = Echo.to_h

    refute h[:inputSchema].key?(:"$schema")
    refute h[:outputSchema].key?(:"$schema")
    assert_equal({ type: "string", minLength: 1 }, h.dig(:inputSchema, :properties, :message))
    assert_equal({ type: "string" }, h.dig(:outputSchema, :properties, :message))
    integer = Class.new(FolkloreMcp::Tool) do
      tool_name "scratch"
      input_schema { required(:n).filled(:integer) }
      output_schema { required(:n).filled(:integer) }
    end
    assert_equal({ type: "integer" }, integer.to_h.dig(:inputSchema, :properties, :n))
    assert_equal({ type: "integer" }, integer.to_h.dig(:outputSchema, :properties, :n))
  ensure
    FolkloreMcp::Tool.registered_tools.delete(integer)
  end

  test "a missing actor returns Unauthenticated" do
    response = Echo.call(message: "hi")

    assert response.to_h[:isError]
    assert_match(/Unauthenticated/, text_of(response))
  end

  test "a successful text call carries structured content beside the text" do
    response = Echo.call(message: "hi", server_context: actor_context(agent: "ping"))

    refute response.to_h[:isError]
    assert_equal "member/ping: hi", text_of(response)
    assert_equal({ message: "hi", actor: "member/ping" }, response.to_h[:structuredContent])
  end

  test "a json call puts the JSON in the text and the data in structured content" do
    response = Echo.call(message: "hi", format: "json", server_context: actor_context)

    assert_equal({ "message" => "hi", "actor" => "member/default" }, JSON.parse(text_of(response)))
    assert_equal({ message: "hi", actor: "member/default" }, response.to_h[:structuredContent])
  end

  test "a record validation failure is reported as Invalid" do
    response = Echo.call(message: "hi", fail_with: "invalid", server_context: actor_context)

    assert response.to_h[:isError]
    assert_match(/\AInvalid: Name can't be blank/, text_of(response))
  end

  test "an unexpected exception is reported as exactly Internal error, with no exception text" do
    response = Echo.call(message: "hi", fail_with: "boom", server_context: actor_context)

    assert response.to_h[:isError]
    assert_equal "Internal error", text_of(response)
  end

  test "domain input errors are reported with their message, not as Internal error" do
    { "dir" => /\AInvalid: path segments cannot be/, "stale" => /\AInvalid: stale_after must be/,
      "agent" => /\AInvalid: agent/, "missing" => /\ANot found: asset\z/, "conflict" => /\AConflict/ }.each do |mode, pattern|
      response = Echo.call(message: "hi", fail_with: mode, server_context: actor_context)

      assert response.to_h[:isError], mode
      assert_match pattern, text_of(response), mode
    end
  end

  test "every registered error answers with the prefix its status maps to" do
    expected = { not_found: "Not found", forbidden: "Forbidden", conflict: "Conflict", unprocessable_content: "Invalid" }
    task_codes = { "not_a_task" => "Not a task", "already_claimed" => "Already claimed",
                   "no_pending_task" => "No pending task", "wrong_claimer" => "Wrong claimer" }

    DomainErrors::ENTRIES.each do |klass, entry|
      assert_equal task_codes.fetch(entry.code) { expected.fetch(entry.status) }, FolkloreMcp::Tool.prefix_for(entry), klass.name
    end
  end

  test "a json-format failure carries the error's code beside the text" do
    response = Echo.call(message: "hi", format: "json", fail_with: "dir", server_context: actor_context)

    assert response.to_h[:isError]
    payload = JSON.parse(text_of(response))
    assert_equal "invalid_path", payload["code"]
    assert_match(/\AInvalid: path segments cannot be/, payload["error"])
    assert_equal payload, response.to_h[:structuredContent].stringify_keys
  end

  test "an unexpected exception re-raises when MCP_RAISE_ERRORS is set" do
    ENV["MCP_RAISE_ERRORS"] = "1"
    assert_raises(RuntimeError) { Echo.call(message: "hi", fail_with: "boom", server_context: actor_context) }
  ensure
    ENV.delete("MCP_RAISE_ERRORS")
  end

  test "error_response in json format wraps the message" do
    tool = Echo.new
    response = tool.error_response("Not found: x", format: "json")

    assert response.to_h[:isError]
    assert_equal({ "error" => "Not found: x" }, JSON.parse(text_of(response)))
    assert_equal "Not found: x", tool.error_response("Not found: x").to_h[:content].first[:text]
  end
end
