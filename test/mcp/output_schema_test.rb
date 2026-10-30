require "test_helper"

# Every tool's happy path, with its structured content checked against the
# outputSchema it advertises in tools/list. A tool added without a case here
# fails the first test, so the contract cannot drift unchecked.
class FolkloreMcp::OutputSchemaTest < ActiveSupport::TestCase
  # Cases share one database, so each asset gets a name of its own.
  def create(name, content: "body", path: "member/notes", **attrs)
    ::Assets::Create.mutate(actor: actor_for(:member_default), path:, name: "#{SecureRandom.hex(4)}-#{name}", content:, **attrs)
  end

  def task(name)
    ::Tasks::Add.mutate(actor: actor_for(:member_default), path: "member/tasks", name: "#{SecureRandom.hex(4)}-#{name}", content: "do it")
  end

  def claimed(name)
    task(name).tap { |t| ::Tasks::Claim.mutate(actor: actor_for(:member_default), slug: t.slug) }
  end

  def edited(name)
    create(name, content: "v1").tap { |a| ::Assets::Update.mutate(actor: actor_for(:member_default), slug: a.slug, content: "v2") }
  end

  # Each case returns the arguments for one successful call.
  CASES = {
    "activity" => ->(t) { t.create("a.md"); {} },
    "add_tag" => ->(t) { { slug: t.create("a.md").slug, tag: "ruby" } },
    "add_task" => ->(_) { { path: "member/tasks", name: "t.md", content: "do it" } },
    "append" => ->(t) { { slug: t.create("a.md").slug, text: "more" } },
    "bulk_read" => ->(t) { { slugs: [ t.create("a.md").slug, "00000000" ], format: "json" } },
    "claim_task" => ->(t) { { slug: t.task("t.md").slug } },
    "complete_task" => ->(t) { { slug: t.claimed("t.md").slug } },
    "create" => ->(_) { { path: "member/notes", name: "new.md", content: "x" } },
    "delete" => ->(t) { { slug: t.create("a.md").slug } },
    "fail_task" => ->(t) { { slug: t.claimed("t.md").slug, reason: "blocked" } },
    "get_last_session" => ->(t) { ::Checkpoints::Write.mutate(actor: t.actor_for(:member_default), content: "state"); {} },
    "get_pending_tasks" => ->(t) { t.task("t.md"); { path_prefix: "member" } },
    "list" => ->(t) { t.create("a.md", tags: %w[ruby]); { path: "member" } },
    "read" => ->(t) { { slug: t.create("a.md").slug } },
    "read_path" => ->(t) { { location: t.create("a.md").location } },
    "remove_tag" => ->(t) { { slug: t.create("a.md", tags: %w[ruby]).slug, tag: "ruby" } },
    "restore" => ->(t) { { slug: t.create("a.md").tap { |a| ::Assets::Delete.mutate(actor: t.actor_for(:member_default), slug: a.slug) }.slug } },
    "search" => ->(t) { t.create("a.md", content: "needle"); { q: "needle" } },
    "set_stale_after" => ->(t) { { slug: t.create("a.md").slug, stale_after: "2030-01-01" } },
    "set_status" => ->(t) { { slug: t.create("a.md").slug, status: "open" } },
    "tags" => ->(t) { t.create("a.md", tags: %w[ruby]); {} },
    "update" => ->(t) { { slug: t.create("a.md").slug, content: "new" } },
    "update_last_session" => ->(_) { { content: "state" } },
    "upsert" => ->(_) { { path: "member/notes", name: "u.md", content: "x" } },
    "verify" => ->(t) { { slug: t.create("a.md").slug } },
    "versions" => ->(t) { { slug: t.edited("a.md").slug } }
  }.freeze

  def domain_tools
    FolkloreMcp.tool_classes.select { |tool| tool.name.start_with?("FolkloreMcp::Tools::") }
  end

  test "every domain tool has a happy-path case" do
    assert_equal domain_tools.map(&:name_value).sort, CASES.keys.sort
  end

  test "every tool's structured content matches its outputSchema" do
    domain_tools.each do |tool|
      args = CASES.fetch(tool.name_value).call(self)
      response = tool.call(**args, server_context: actor_context).to_h

      refute response[:isError], "#{tool.name_value}: #{response[:content].inspect}"
      structured = response[:structuredContent]
      assert structured, "#{tool.name_value} returned no structured content"
      # Through JSON, as a client receives it.
      tool.output_schema.validate_result(JSON.parse(JSON.generate(structured)))
    rescue MCP::Tool::OutputSchema::ValidationError => e
      flunk "#{tool.name_value}: #{e.message}"
    end
  end
end
