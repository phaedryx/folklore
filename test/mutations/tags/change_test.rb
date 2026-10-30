require "test_helper"

class Tags::ChangeTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "", tags: %w[shell])
  end

  test "adds and removes tags, recording one event per tag and nothing else" do
    Tags::Change.mutate(actor: @actor, asset: @asset, add: %w[ruby], remove: %w[shell])

    assert_equal %w[ruby], @asset.reload.tags.pluck(:name)
    events = Event.where(asset: @asset).where.not(action: "asset_created").order(:id)
    assert_equal [ [ "tag_added", { "tag" => "ruby" } ], [ "tag_removed", { "tag" => "shell" } ] ], events.pluck(:action, :metadata)
    assert_equal [ "ping" ], events.pluck(:actor_agent).uniq
  end

  test "reuses an existing tag row" do
    Tags::Change.mutate(actor: @actor, asset: @asset, add: %w[shell2])
    other = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "other.md", content: "")

    assert_no_difference -> { Tag.count } do
      Tags::Change.mutate(actor: @actor, asset: other, add: %w[shell2])
    end
  end

  test "leaves the asset row alone: touching it is the caller's call" do
    assert_no_changes -> { @asset.reload.lock_version } do
      Tags::Change.mutate(actor: @actor, asset: @asset, add: %w[ruby])
    end
  end
end
