require "test_helper"

class Assets::ReadTest < ActiveSupport::TestCase
  setup do
    @asset = Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "hello.md", content: "hi")
  end

  test "returns the live asset by slug" do
    assert_equal @asset, Assets::Read.query(slug: @asset.slug, actor: actor_for(:member_default))
  end

  test "any member reads any live asset" do
    assert_equal @asset, Assets::Read.query(slug: @asset.slug, actor: actor_for(:other_default))
  end

  test "raises NotFoundError for an unknown or deleted slug" do
    assert_raises(Assets::NotFoundError) { Assets::Read.query(slug: "00000000", actor: actor_for(:member_default)) }

    @asset.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { Assets::Read.query(slug: @asset.slug, actor: actor_for(:member_default)) }
  end
end
