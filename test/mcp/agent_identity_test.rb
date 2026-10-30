require "test_helper"

# Every write names its agent. On a shared token the `agent` argument picks
# which agent that is, for every write tool alike, so one agent's claims,
# checkpoint and asset writes carry the same label. A token that is not
# shared acts only as its own agent.
class FolkloreMcp::AgentIdentityTest < ActiveSupport::TestCase
  Assets = FolkloreMcp::Tools::Assets
  Tags = FolkloreMcp::Tools::Tags

  def domain_tools
    FolkloreMcp.tool_classes.select { |tool| tool.name.start_with?("FolkloreMcp::Tools::") }
  end

  test "every write tool takes an optional agent" do
    domain_tools.reject { |tool| tool.annotations_value.read_only_hint }.each do |tool|
      schema = tool.to_h[:inputSchema]

      assert_includes schema[:properties].keys.map(&:to_s), "agent", tool.name_value
      refute_includes Array(schema[:required]).map(&:to_s), "agent", tool.name_value
    end
  end

  test "on a shared token, asset writes are attributed to the passed agent" do
    ping = actor_context(:member_default)
    response = Assets::Create.call(path: "member/notes", name: "a.md", content: "one", agent: "ping", server_context: ping)
    refute response.to_h[:isError], text_of(response)
    slug = response.to_h[:structuredContent][:slug]

    Assets::Update.call(slug:, content: "two", agent: "pong", server_context: ping)
    Tags::Add.call(slug:, tag: "x", agent: "pong", server_context: ping)
    Assets::Verify.call(slug:, agent: "ping", server_context: ping)

    asset = Asset.find_by!(slug:)
    assert_equal "ping", asset.created_by_agent
    assert_equal "pong", asset.updated_by_agent
    assert_equal "ping", asset.verified_by_agent
    # Tagging is an edit, so it records asset_updated beside tag_added.
    assert_equal [ %w[asset_created ping], %w[asset_updated pong], %w[tag_added pong], %w[asset_updated pong], %w[asset_verified ping] ],
                 Event.where(asset_id: asset.id).order(:id).pluck(:action, :actor_agent)
  end

  test "a token that is not shared cannot write as another agent, and nothing is written" do
    assert_no_difference -> { Asset.count } do
      response = Assets::Create.call(path: "other/notes", name: "a.md", content: "x", agent: "ping",
                                     server_context: actor_context(:other_default))

      assert response.to_h[:isError]
      assert_match(/\AInvalid: token "default" is not shared/, text_of(response))
    end
  end

  test "a token that is not shared may name its own agent" do
    response = Assets::Create.call(path: "other/notes", name: "a.md", content: "x", agent: "default",
                                   server_context: actor_context(:other_default))

    refute response.to_h[:isError], text_of(response)
  end
end
