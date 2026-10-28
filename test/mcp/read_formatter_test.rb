require "test_helper"

class FolkloreMcp::ReadFormatterTest < ActiveSupport::TestCase
  def build(name, **attrs)
    Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name:,
                  created_by_token: tokens(:member_default), created_by_agent: "ping", **attrs)
  end

  test "metadata fields are the documented set" do
    assert_equal %i[name path content_type kind status owner tags created_at updated_at backlinks created_by updated_by verified_by version],
                 FolkloreMcp::ReadFormatter::METADATA_FIELDS
  end

  test "no flags returns exactly the content" do
    asset = build("a.md", content: "just content")

    assert_equal "just content", FolkloreMcp::ReadFormatter.call(asset, requested: [])
  end

  test "text fields render in documented order, then content after a separator" do
    asset = build("a.md", content: "body", content_type: "text/markdown")
    AssetTag.create!(asset:, tag: Tag.create!(name: "ruby"))

    text = FolkloreMcp::ReadFormatter.call(asset, requested: %i[content created_by tags name version])

    assert_equal "name: a.md\ntags: ruby\ncreated_by: member/ping\nversion: 0\n---\nbody", text
  end

  test "backlinks render as slug and location lines in text and as objects in json" do
    target = build("target.md")
    source = build("source.md")
    Link.create!(src_asset: source, dst_asset: target, dst_ref: target.slug, kind: "wikilink")

    text = FolkloreMcp::ReadFormatter.call(target, requested: %i[backlinks])
    json = FolkloreMcp::ReadFormatter.call(target, requested: %i[backlinks], format: "json")

    assert_equal "backlinks:\n#{source.slug}  member/notes/source.md", text
    assert_equal({ slug: target.slug, backlinks: [ { slug: source.slug, location: "member/notes/source.md", name: "source.md" } ] }, json)
  end

  test "json with no flags is the full serialized asset; with flags only those fields plus slug" do
    asset = build("a.md", content: "body")

    full = FolkloreMcp::ReadFormatter.call(asset, requested: [], format: "json")
    partial = FolkloreMcp::ReadFormatter.call(asset, requested: %i[owner created_by], format: "json")

    assert_equal Assets::Serializer.call(asset), full
    assert_equal({ slug: asset.slug, owner: "member", created_by: { handle: "member", agent: "ping" } }, partial)
  end

  test "absent actors render as empty text" do
    asset = build("a.md")

    assert_equal "verified_by: ", FolkloreMcp::ReadFormatter.call(asset, requested: %i[verified_by])
  end
end
