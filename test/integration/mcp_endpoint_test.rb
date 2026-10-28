require "test_helper"

class McpEndpointTest < ActionDispatch::IntegrationTest
  MCP_HEADERS = {
    "Content-Type" => "application/json",
    "Accept" => "application/json, text/event-stream"
  }.freeze

  def auth_headers(plaintext = "flk_test_member")
    MCP_HEADERS.merge("Authorization" => "Bearer #{plaintext}")
  end

  def rpc(method, params = {}, id: 1)
    { jsonrpc: "2.0", id:, method:, params: }.to_json
  end

  def initialize_payload(protocol_version: "2025-03-26")
    rpc("initialize", { protocolVersion: protocol_version, capabilities: {}, clientInfo: { name: "test", version: "1" } })
  end

  test "401 with no Authorization header" do
    post "/mcp", params: initialize_payload, headers: MCP_HEADERS

    assert_equal 401, response.status
    assert_equal "Bearer", response.headers["WWW-Authenticate"]
    assert_equal({ "error" => "missing or invalid Authorization header" }, JSON.parse(response.body))
  end

  test "401 with an unknown bearer token" do
    post "/mcp", params: initialize_payload, headers: auth_headers("flk_garbage")

    assert_equal 401, response.status
  end

  test "401 with a revoked token" do
    post "/mcp", params: initialize_payload, headers: auth_headers("flk_test_member_revoked")

    assert_equal 401, response.status
    assert_match(/revoked/, response.body)
  end

  test "initialize names the server folklore and carries the instructions" do
    post "/mcp", params: initialize_payload, headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "folklore", body.dig("result", "serverInfo", "name")
    instructions = body.dig("result", "instructions").to_s
    assert_match(/get_last_session/, instructions)
    assert_match(/update_last_session/, instructions)
    assert_match(/verify/, instructions)
    assert_match(/stale: true/, instructions)
    assert_match(/agent/, instructions)
  end

  test "tools/list returns an array of registered tools with annotations" do
    post "/mcp", params: rpc("tools/list", {}, id: 2), headers: auth_headers

    assert_response :success
    tools = JSON.parse(response.body).dig("result", "tools")
    assert_kind_of Array, tools
    echo = tools.find { |t| t["name"] == "echo" }
    assert echo, "the test echo tool should be listed"
    assert_equal true, echo.dig("annotations", "readOnlyHint")
    assert echo["outputSchema"]
  end

  test "tools/call runs with the token's actor" do
    post "/mcp", params: rpc("tools/call", { name: "echo", arguments: { message: "hi" } }, id: 3), headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    refute body.dig("result", "isError"), body.inspect
    assert_equal "member/default: hi", body.dig("result", "content", 0, "text")
    assert_equal({ "message" => "hi", "actor" => "member/default" }, body.dig("result", "structuredContent"))
  end

  test "last_used_at is written on an authenticated call" do
    token = tokens(:member_default)
    assert_nil token.last_used_at

    post "/mcp", params: initialize_payload, headers: auth_headers

    assert_response :success
    assert_in_delta Time.current, token.reload.last_used_at, 5.seconds
  end

  test "last_used_at is not rewritten within a minute" do
    token = tokens(:member_default)
    token.update_column(:last_used_at, 30.seconds.ago)

    post "/mcp", params: initialize_payload, headers: auth_headers

    assert_response :success
    assert_in_delta 30.seconds.ago, token.reload.last_used_at, 2.seconds
  end

  test "tools/call with an argument the tool does not take answers Invalid arguments" do
    post "/mcp", params: rpc("tools/call", { name: "echo", arguments: { message: "hi", agent: "ping" } }, id: 4), headers: auth_headers

    assert_response :success
    body = JSON.parse(response.body)
    assert body.dig("result", "isError"), body.inspect
    assert_match(/\AInvalid arguments: /, body.dig("result", "content", 0, "text"))
  end

  test "every tool's input schema is closed" do
    FolkloreMcp.tool_classes.each do |tool|
      assert_equal false, tool.input_schema_value.to_h[:additionalProperties], "#{tool.name_value} accepts unknown arguments"
    end
  end
end
