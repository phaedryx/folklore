require "test_helper"

# A token's scopes decide which tools it may call. Write-ness comes from each
# tool's read_only annotation, so the annotations are pinned here too: a wrong
# annotation is an authorization bug, not a cosmetic one.
class FolkloreMcp::ScopesTest < ActiveSupport::TestCase
  READ_ONLY_TOOLS = %w[activity bulk_read get_last_session get_pending_tasks list read read_path search tags versions].freeze

  def domain_tools
    FolkloreMcp.tool_classes.select { |tool| tool.name.start_with?("FolkloreMcp::Tools::") }
  end

  test "exactly these tools are read-only" do
    read_only = domain_tools.select { |tool| tool.annotations_value.read_only_hint }.map(&:name_value).sort

    assert_equal READ_ONLY_TOOLS, read_only
  end

  test "a read-only token cannot call a write tool, and nothing is written" do
    assert_no_difference -> { Asset.count } do
      response = FolkloreMcp::Tools::Assets::Create.call(path: "member/notes", name: "a.md", content: "x",
                                                         server_context: actor_context(:member_readonly))

      assert response.to_h[:isError]
      assert_equal "Forbidden: token lacks write scope", text_of(response)
    end
  end

  test "every write tool refuses a read-only token" do
    domain_tools.reject { |tool| tool.annotations_value.read_only_hint }.each do |tool|
      response = tool.call(server_context: actor_context(:member_readonly))

      assert_equal "Forbidden: token lacks write scope", text_of(response), tool.name_value
    end
  end

  test "a read-only token can still call read tools" do
    asset = ::Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "r.md", content: "body")

    response = FolkloreMcp::Tools::Assets::Read.call(slug: asset.slug, server_context: actor_context(:member_readonly))

    refute response.to_h[:isError]
    assert_equal "body", text_of(response)
  end

  test "every read-only tool refuses a write-only token" do
    domain_tools.select { |tool| tool.annotations_value.read_only_hint }.each do |tool|
      response = tool.call(server_context: actor_context(:member_writeonly))

      assert_equal "Forbidden: token lacks read scope", text_of(response), tool.name_value
    end
  end

  test "a write-only token can still call write tools" do
    response = FolkloreMcp::Tools::Assets::Create.call(path: "member/notes", name: "w.md", content: "x",
                                                       server_context: actor_context(:member_writeonly))

    refute response.to_h[:isError], text_of(response)
  end

  test "a web session has no token and is not scope-checked" do
    response = FolkloreMcp::Tools::Assets::Create.call(path: "member/notes", name: "w.md", content: "x",
                                                       server_context: { actor: Actor.for_user(users(:member)) })

    refute response.to_h[:isError], text_of(response)
  end
end
