require "test_helper"

class Versions::ListTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  test "returns an asset's versions newest first" do
    asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "v1")
    Assets::Update.mutate(actor: @actor, slug: asset.slug, content: "v2")
    Assets::Update.mutate(actor: @actor, slug: asset.slug, content: "v3")

    assert_equal %w[v2 v1], Versions::List.query(slug: asset.slug, actor: @actor).map(&:content)
  end

  test "an asset with no versions yields an empty relation, including a deleted one" do
    asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "hi")
    assert_empty Versions::List.query(slug: asset.slug, actor: @actor)

    asset.update!(deleted_at: Time.current)
    assert_empty Versions::List.query(slug: asset.slug, actor: @actor)
  end

  test "raises NotFoundError for an unknown slug" do
    assert_raises(Assets::NotFoundError) { Versions::List.query(slug: "00000000", actor: @actor) }
  end
end
