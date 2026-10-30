require "test_helper"

class Versions::ReadTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "v1")
    Assets::Update.mutate(actor: @actor, slug: @asset.slug, content: "v2")
  end

  test "returns one of a live asset's versions" do
    assert_equal "v1", Versions::Read.query(slug: @asset.slug, id: @asset.versions.sole.id, actor: @actor).content
  end

  test "raises for a version on another asset, or an archived asset" do
    other = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "other.md", content: "a")
    Assets::Update.mutate(actor: @actor, slug: other.slug, content: "b")

    assert_raises(Versions::NotFoundError) { Versions::Read.query(slug: @asset.slug, id: other.versions.sole.id, actor: @actor) }

    Assets::Delete.mutate(actor: @actor, slug: @asset.slug)
    assert_raises(Assets::NotFoundError) { Versions::Read.query(slug: @asset.slug, id: @asset.versions.sole.id, actor: @actor) }
  end
end
