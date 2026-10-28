require "test_helper"

class Links::BacklinksTest < ActiveSupport::TestCase
  def asset(name, **attrs)
    Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name:, **attrs)
  end

  test "returns live assets whose wikilinks resolve to the target" do
    target = asset("target.md")
    source = asset("source.md")
    gone = asset("gone.md", deleted_at: Time.current)
    Link.create!(src_asset: source, dst_asset: target, dst_ref: target.slug, kind: "wikilink")
    Link.create!(src_asset: gone, dst_asset: target, dst_ref: target.slug, kind: "wikilink")

    assert_equal [ source ], Links::Backlinks.query(asset: target).to_a
  end

  test "an asset nobody links to has no backlinks" do
    assert_empty Links::Backlinks.query(asset: asset("lonely.md"))
  end

  # Only resolved links count: a link left dangling (its target archived, or
  # never existing) names the slug in dst_ref but resolves to nothing.
  test "a dangling link whose dst_ref names the target is not a backlink" do
    target = asset("target.md")
    source = asset("source.md")
    Link.create!(src_asset: source, dst_asset: nil, dst_ref: target.slug, kind: "wikilink")

    assert_empty Links::Backlinks.query(asset: target)
  end
end
