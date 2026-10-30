require "test_helper"

# Tenancy in phase 1: every member reads every workspace. Each read query
# takes the caller as `actor:`, and none of them narrows by it; this pins
# that, query by query, so a phase that adds private workspaces changes it
# here on purpose. The write rule (owner only) is enforced in the mutations,
# through Assets.writable! and the owner checks in Create, Delete and Restore,
# and is tested with them.
class ReadAuthorizationTest < ActiveSupport::TestCase
  setup do
    @owner = actor_for(:member_default)
    @reader = actor_for(:other_default)
    @note = Assets::Create.mutate(actor: @owner, path: "member/notes", name: "shared.md", content: "shared haystack", tags: %w[kept])
    Assets::Update.mutate(actor: @owner, slug: @note.slug, content: "shared haystack, edited")
    @task = Tasks::Add.mutate(actor: @owner, path: "member/queue", name: "job.md", content: "do it")
  end

  test "another member reads an asset by slug, by path and in bulk" do
    assert_equal @note, Assets::Read.query(slug: @note.slug, actor: @reader)
    assert_equal @note, Assets::ReadByPath.query(location: @note.location, actor: @reader)
    assert_equal [ @note ], Assets::BulkRead.query(refs: [ @note.slug ], actor: @reader).items.map(&:asset)
  end

  test "another member lists, browses and searches a workspace that is not theirs" do
    assert_includes Assets::List.query(path: "member", actor: @reader), @note
    assert_includes Assets::List.query(path: "member/notes", tags: %w[kept], actor: @reader), @note
    assert_includes Assets::Browse.query(dir: "member", actor: @reader).folders, "notes"
    assert_equal [ @note ], Assets::Search.query(query: "haystack", actor: @reader).to_a
  end

  test "another member sees the history, tasks and review queue of a workspace that is not theirs" do
    assert_equal 1, Versions::List.query(slug: @note.slug, actor: @reader).size
    assert_equal [ @task ], Tasks::List.query(path_prefix: "member/queue", actor: @reader).to_a

    Assets::SetStaleAfter.mutate(actor: @owner, slug: @note.slug, stale_after: Date.yesterday.iso8601)
    assert_includes Assets::Stale.query(actor: @reader), @note.reload
  end
end
