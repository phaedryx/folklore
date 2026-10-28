require "test_helper"

class Assets::ReadByPathTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "hi")
  end

  test "resolves a location" do
    assert_equal @asset, Assets::ReadByPath.query(location: "member/notes/hello.md", actor: @actor)
  end

  test "resolves path + name" do
    assert_equal @asset, Assets::ReadByPath.query(path: "member/notes", name: "hello.md", actor: @actor)
  end

  test "raises NotFoundError for an unknown location or a deleted asset" do
    assert_raises(Assets::NotFoundError) { Assets::ReadByPath.query(location: "member/notes/missing.md", actor: @actor) }

    @asset.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { Assets::ReadByPath.query(location: "member/notes/hello.md", actor: @actor) }
  end

  test "raises InvalidLocationError when the address is incomplete" do
    assert_raises(Assets::InvalidLocationError) { Assets::ReadByPath.query(path: "member/notes", actor: @actor) }
    assert_raises(Assets::InvalidLocationError) { Assets::ReadByPath.query(location: "hello.md", actor: @actor) }
    assert_raises(Assets::InvalidLocationError) { Assets::ReadByPath.query(location: "member/notes/", actor: @actor) }
  end
end
