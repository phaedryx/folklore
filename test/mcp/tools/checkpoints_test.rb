require "test_helper"

class FolkloreMcp::Tools::CheckpointsTest < ActiveSupport::TestCase
  Get = FolkloreMcp::Tools::Checkpoints::Get
  Update = FolkloreMcp::Tools::Checkpoints::Update

  def ctx(fixture = :member_default, agent: nil)
    actor_context(fixture, agent:)
  end

  test "the checkpoint wire names are registered with annotations and an agent argument" do
    assert_equal "get_last_session", Get.name_value
    assert_equal "update_last_session", Update.name_value
    assert Get.to_h[:annotations][:readOnlyHint]
    assert Update.to_h[:annotations][:idempotentHint]
    [ Get, Update ].each do |tool|
      assert tool.to_h[:outputSchema]
      assert_includes tool.to_h[:inputSchema][:properties].keys.map(&:to_s), "agent"
      assert_match(/agent/, tool.description_value)
    end
    assert_match(/Call this FIRST/, Get.description_value)
  end

  test "get_last_session says exactly that there is none yet, naming handle and agent" do
    response = Get.call(server_context: ctx)

    refute response.to_h[:isError], text_of(response)
    assert_equal "No checkpoint yet for member/default. Call update_last_session before finishing.", text_of(response)
    assert_equal({ agent: "member/default", location: "member/state/default/last_session.md", content: nil }, response.to_h[:structuredContent])
  end

  test "update_last_session then get_last_session round-trips" do
    saved = Update.call(content: "mid-refactor on paths", server_context: ctx)
    refute saved.to_h[:isError], text_of(saved)
    asset = Asset.find_by!(dir: "member/state/default", name: "last_session.md")
    assert_equal "Checkpoint saved to member/state/default/last_session.md (#{asset.slug})", text_of(saved)
    again = Update.call(content: "mid-refactor on paths", server_context: ctx)
    assert_equal "Checkpoint unchanged at member/state/default/last_session.md (#{asset.slug})", text_of(again)

    response = Get.call(server_context: ctx)

    expected = { agent: "member/default", location: "member/state/default/last_session.md", slug: asset.slug,
                 updated_at: asset.updated_at.iso8601, content: "mid-refactor on paths" }
    assert_equal expected, response.to_h[:structuredContent]
    # The content once: the text is the structured content as JSON, as the MCP spec recommends.
    assert_equal expected.stringify_keys, JSON.parse(text_of(response))
  end

  test "update_last_session overwrites the single checkpoint asset" do
    Update.call(content: "first", server_context: ctx)
    Update.call(content: "second", server_context: ctx)

    assert_equal 1, Asset.live.where(name: Checkpoint::NAME).count
    assert_match(/second/, text_of(Get.call(server_context: ctx)))
  end

  test "agents sharing a token keep separate checkpoints through the agent argument" do
    Update.call(content: "ping's place", agent: "ping", server_context: ctx)
    Update.call(content: "pong's place", agent: "pong", server_context: ctx)

    assert_match(/ping's place/, text_of(Get.call(agent: "ping", server_context: ctx)))
    assert_match(/pong's place/, text_of(Get.call(agent: "pong", server_context: ctx)))
    assert_equal "No checkpoint yet for member/default. Call update_last_session before finishing.", text_of(Get.call(server_context: ctx))
  end

  test "get_last_session reads only the caller's own checkpoint" do
    Update.call(content: "theirs", server_context: ctx(:other_default))

    assert_match(/\ANo checkpoint yet for member\/default/, text_of(Get.call(server_context: ctx)))
  end

  test "update_last_session rejects empty content instead of reporting a save that did not happen" do
    Update.call(content: "real", server_context: ctx)

    response = Update.call(content: "", server_context: ctx)

    assert response.to_h[:isError], text_of(response)
    assert_equal "Invalid [empty_content]: checkpoint content cannot be empty", text_of(response)
    assert_match(/real/, text_of(Get.call(server_context: ctx)))
  end

  test "a bad agent name and a missing handle are reported, not internal errors" do
    assert_match(/\AInvalid \[[a-z_]+\]: agent/, text_of(Get.call(agent: "../x", server_context: ctx)))

    handleless = User.create!(email: "nohandle@example.com", name: "No Handle")
    token = Token.create!(user: handleless, agent_name: "default", token_digest: Token.digest("flk_test_nohandle"))
    response = Get.call(server_context: { actor: Actor.for_token(token) })
    assert response.to_h[:isError]
    assert_match(/\AInvalid \[[a-z_]+\]: .*handle/, text_of(response))
  end
end
