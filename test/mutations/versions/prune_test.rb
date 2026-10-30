require "test_helper"

class Versions::PruneTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
  end

  def asset_with_versions(name, count)
    asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name:, content: "v0")
    count.times { |i| Assets::Update.mutate(actor: @actor, slug: asset.slug, content: "v#{i + 1}") }
    asset
  end

  def contents(asset)
    asset.versions.order(:created_at, :id).pluck(:content)
  end

  test "keeps each asset's newest versions and deletes the rest" do
    a = asset_with_versions("a.md", 4)
    b = asset_with_versions("b.md", 1)

    deleted = Versions::Prune.mutate(keep: 2)

    assert_equal 2, deleted
    assert_equal %w[v2 v3], contents(a)
    assert_equal %w[v0], contents(b)
  end

  test "orders by created_at, not id, since an import can load old versions with new ids" do
    asset = asset_with_versions("a.md", 2)
    Version.create!(asset:, content: "ancient", created_at: 1.year.ago)

    Versions::Prune.mutate(keep: 2)

    assert_equal %w[v0 v1], contents(asset)
  end

  test "touches only the given assets" do
    a = asset_with_versions("a.md", 3)
    b = asset_with_versions("b.md", 3)

    Versions::Prune.mutate(keep: 1, assets: Asset.where(id: a.id))

    assert_equal %w[v2], contents(a)
    assert_equal %w[v0 v1 v2], contents(b)
  end

  test "keep 0 deletes every version" do
    asset = asset_with_versions("a.md", 2)

    Versions::Prune.mutate(keep: 0)

    assert_empty contents(asset)
  end

  test "refuses a negative or non-integer keep" do
    [ -1, "lots", nil ].each do |keep|
      assert_raises(Versions::InvalidKeepError) { Versions::Prune.mutate(keep:) }
    end
  end
end
