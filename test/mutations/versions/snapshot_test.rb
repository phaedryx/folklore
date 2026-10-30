require "test_helper"

class Versions::SnapshotTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "v1",
                                   content_type: "text/markdown")
  end

  test "keeps the asset's current content as a version, stamped with the actor" do
    version = Versions::Snapshot.mutate(actor: @actor, asset: @asset)

    assert_equal [ version ], @asset.versions.to_a
    assert_equal [ "v1", "text/markdown" ], [ version.content, version.content_type ]
    assert_equal [ users(:member), @actor.token, "ping" ], [ version.actor_user, version.actor_token, version.actor_agent ]
  end
end
