require "test_helper"

class Assets::StaleTest < ActiveSupport::TestCase
  def note(name, path: "member/notes", actor: actor_for(:member_default), stale_after: nil)
    asset = Assets::Create.mutate(actor:, path:, name:, content: "body")
    asset.update!(stale_after:) if stale_after
    asset
  end

  test "returns live assets whose review date has passed, most overdue first" do
    note("recent.md", stale_after: Date.current - 1)
    note("old.md", stale_after: Date.current - 30)
    note("upcoming.md", stale_after: Date.current + 1)
    note("today.md", stale_after: Date.current)
    note("undated.md")
    note("gone.md", stale_after: Date.current - 5).update!(deleted_at: Time.current)

    assert_equal %w[old.md recent.md], Assets::Stale.query(actor: actor_for(:member_default)).map(&:name)
  end

  test "path_prefix scopes the queue" do
    note("mine.md", stale_after: Date.current - 1)
    note("theirs.md", path: "other/notes", actor: actor_for(:other_default), stale_after: Date.current - 1)

    assert_equal %w[mine.md], Assets::Stale.query(path_prefix: "member", actor: actor_for(:member_default)).map(&:name)
  end
end
