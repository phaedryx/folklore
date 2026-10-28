require "test_helper"

class Events::RecordTest < ActiveSupport::TestCase
  def asset
    @asset ||= Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name: "a.md")
  end

  test "persists an event stamped with the actor's user, token and agent" do
    actor = actor_for(:member_default, agent: "ping")

    event = assert_difference -> { Event.count }, 1 do
      Events::Record.mutate(actor:, action: "asset_created", asset:)
    end

    assert_equal users(:member).id, event.actor_user_id
    assert_equal tokens(:member_default).id, event.actor_token_id
    assert_equal "ping", event.actor_agent
    assert_equal asset.id, event.asset_id
    assert_equal({}, event.metadata)
  end

  test "a web actor has no token and the web agent" do
    event = Events::Record.mutate(actor: Actor.for_user(users(:member)), action: "asset_updated", asset:)

    assert_nil event.actor_token_id
    assert_equal "web", event.actor_agent
  end

  test "keeps metadata" do
    event = Events::Record.mutate(actor: actor_for(:member_default), action: "version_restored", asset:,
                                  metadata: { "restored_from_version_id" => 7 })

    assert_equal({ "restored_from_version_id" => 7 }, event.reload.metadata)
  end

  test "an asset is optional" do
    event = Events::Record.mutate(actor: actor_for(:member_default), action: "asset_created")

    assert_nil event.asset_id
  end

  test "an unknown action is refused" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Events::Record.mutate(actor: actor_for(:member_default), action: "asset_exploded", asset:)
    end
  end
end
