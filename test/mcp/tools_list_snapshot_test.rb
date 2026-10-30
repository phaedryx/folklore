require "test_helper"

# tools/list is the contract agents and their skills depend on. Any change to a
# tool's name, description, schemas or annotations fails this test until the
# snapshot is rewritten on purpose:
#
#   UPDATE_SNAPSHOT=1 bin/rails test test/mcp/tools_list_snapshot_test.rb
#
# and the diff to test/mcp/tools_list.snapshot.json is committed with the change.
class FolkloreMcp::ToolsListSnapshotTest < ActionDispatch::IntegrationTest
  SNAPSHOT = Rails.root.join("test/mcp/tools_list.snapshot.json")

  WIRE_NAMES = %w[
    activity add_tag add_task append claim_task complete_task create delete fail_task
    get_last_session get_pending_tasks list move read remove_tag restore search set_stale_after
    set_status tags update update_last_session upsert verify versions
  ].freeze

  # Test-only tools (test/support) live outside this namespace.
  def domain_tools
    FolkloreMcp.tool_classes.select { |tool| tool.name.start_with?("FolkloreMcp::Tools::") }
  end

  def listing
    domain_tools.map(&:to_h).sort_by { |tool| tool[:name] }
  end

  def rendered
    "#{JSON.pretty_generate(listing)}\n"
  end

  test "the domain tools are exactly the phase 1 wire names" do
    assert_equal WIRE_NAMES, domain_tools.map(&:name_value).sort
  end

  test "only domain tools are registered outside a test that registers its own" do
    assert_equal domain_tools, FolkloreMcp.tool_classes
  end

  test "tools/list matches the committed snapshot" do
    if ENV["UPDATE_SNAPSHOT"] == "1"
      SNAPSHOT.write(rendered)
      skip "snapshot rewritten"
    end

    assert SNAPSHOT.exist?, "no snapshot; run with UPDATE_SNAPSHOT=1"
    assert_equal SNAPSHOT.read, rendered, "tools/list changed; rerun with UPDATE_SNAPSHOT=1 if this is deliberate"
  end

  test "the served tools/list is what the snapshot records" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                            "Authorization" => "Bearer flk_test_member" }

    served = JSON.parse(response.body).dig("result", "tools").select { |tool| WIRE_NAMES.include?(tool["name"]) }
    assert_equal JSON.parse(SNAPSHOT.read), served.sort_by { |tool| tool["name"] }
  end
end
