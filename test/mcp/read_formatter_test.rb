require "test_helper"

class FolkloreMcp::ReadFormatterTest < ActiveSupport::TestCase
  def build(name, **attrs)
    Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name:,
                  created_by_token: tokens(:member_default), created_by_agent: "ping", **attrs)
  end

  test "the fields are the documented set" do
    assert_equal %w[content name path content_type kind status owner tags created_at updated_at backlinks created_by updated_by verified_by version],
                 FolkloreMcp::ReadFormatter::FIELDS
  end

  test "no include is the full serialized asset" do
    asset = build("a.md", content: "body")

    assert_equal Assets::Serializer.call(asset), FolkloreMcp::ReadFormatter.call(asset, include: nil)
  end

  test "include returns the slug, then the fields in documented order, then content" do
    asset = build("a.md", content: "body", content_type: "text/markdown")
    AssetTag.create!(asset:, tag: Tag.create!(name: "ruby"))

    data = FolkloreMcp::ReadFormatter.call(asset, include: %w[content created_by tags name owner version])

    assert_equal({ slug: asset.slug, name: "a.md", owner: "member", tags: %w[ruby],
                   created_by: { handle: "member", agent: "ping" }, version: 0, content: "body" }, data)
    assert_equal %i[slug name owner tags created_by version content], data.keys
  end

  test "backlinks are the live assets that link here" do
    target = build("target.md")
    source = build("source.md")
    Link.create!(src_asset: source, dst_asset: target, dst_ref: target.slug, kind: "wikilink")

    assert_equal({ slug: target.slug, backlinks: [ { slug: source.slug, location: "member/notes/source.md", name: "source.md" } ] },
                 FolkloreMcp::ReadFormatter.call(target, include: %w[backlinks]))
  end
end
