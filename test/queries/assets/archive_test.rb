require "test_helper"

class Assets::ArchiveTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  test "lists the workspace's tombstoned assets, most recently deleted first" do
    live = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "live.md")
    older = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "older.md")
    newer = Assets::Create.mutate(actor: @actor, path: "member/scripts", name: "newer.md")
    theirs = Assets::Create.mutate(actor: actor_for(:other_default), path: "other/notes", name: "theirs.md")
    older.update!(deleted_at: 2.days.ago)
    newer.update!(deleted_at: 1.day.ago)
    theirs.update!(deleted_at: Time.current)

    result = Assets::Archive.query(handle: "member", actor: @actor)

    assert_equal [ newer, older ], result.to_a
    refute_includes result, live
  end
end
