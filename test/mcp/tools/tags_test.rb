require "test_helper"

class FolkloreMcp::Tools::TagsTest < ActiveSupport::TestCase
  Tools = FolkloreMcp::Tools::Tags

  def ctx(fixture = :member_default)
    actor_context(fixture)
  end

  def create(name, path: "member/notes", tags: [])
    ::Assets::Create.mutate(actor: actor_for(:member_default), path:, name:, content: "", tags:)
  end

  test "the tag wire names are registered" do
    names = FolkloreMcp.tool_classes.map(&:name_value)
    assert_includes names, "tags"
    assert_includes names, "add_tag"
    assert_includes names, "remove_tag"
  end

  test "add_tag and remove_tag round-trip, normalizing the name" do
    asset = create("t.md")

    add = Tools::Add.call(slug: asset.slug, tag: " Important ", server_context: ctx)
    refute add.to_h[:isError], text_of(add)
    assert_equal "Tagged #{asset.slug} with important", text_of(add)
    assert_equal({ slug: asset.slug, tag: "important", tags: [ "important" ], changed: true }, add.to_h[:structuredContent])

    remove = Tools::Remove.call(slug: asset.slug, tag: "important", server_context: ctx)
    assert_equal "Removed tag important from #{asset.slug}", text_of(remove)
    assert_equal [], remove.to_h[:structuredContent][:tags]
  end

  test "add_tag of a tag already there and remove_tag of one not there succeed, reporting no change" do
    asset = create("t.md", tags: %w[ruby])

    add = Tools::Add.call(slug: asset.slug, tag: "ruby", server_context: ctx)
    refute add.to_h[:isError]
    assert_equal "#{asset.slug} already has tag ruby", text_of(add)
    assert_equal false, add.to_h[:structuredContent][:changed]

    remove = Tools::Remove.call(slug: asset.slug, tag: "python", server_context: ctx)
    refute remove.to_h[:isError]
    assert_equal "#{asset.slug} does not have tag python", text_of(remove)
    assert_equal({ slug: asset.slug, tag: "python", tags: [ "ruby" ], changed: false }, remove.to_h[:structuredContent])
  end

  test "add_tag and remove_tag report not found and forbidden" do
    asset = create("t.md", tags: %w[ruby])

    assert_equal "Not found [not_found]: 00000000", text_of(Tools::Add.call(slug: "00000000", tag: "x", server_context: ctx))
    assert_match(/\AForbidden/, text_of(Tools::Add.call(slug: asset.slug, tag: "x", server_context: ctx(:other_default))))
    assert_match(/\AInvalid \[[a-z_]+\]: tag is required/, text_of(Tools::Add.call(slug: asset.slug, tag: " ", server_context: ctx)))
  end

  test "a tag over the length limit is Invalid from add_tag and from create, not Internal error" do
    asset = create("t.md")
    long = "t" * (Tag::MAX_NAME_LENGTH + 1)

    assert_equal "Invalid [invalid_tag]: tag is 101 characters, over the 100 character limit",
                 text_of(Tools::Add.call(slug: asset.slug, tag: long, server_context: ctx))
    create_response = FolkloreMcp::Tools::Assets::Create.call(path: "member/notes", name: "u.md", tags: [ long ], server_context: ctx)
    assert_equal "Invalid [invalid_tag]: tag is 101 characters, over the 100 character limit", text_of(create_response)
    update_response = FolkloreMcp::Tools::Assets::Update.call(slug: asset.slug, tags: [ long ], server_context: ctx)
    assert_equal "Invalid [invalid_tag]: tag is 101 characters, over the 100 character limit", text_of(update_response)
  end

  test "tags enumerates counts, scoped by within, or says there are none" do
    create("a.md", tags: %w[shell])
    create("b.md", tags: %w[shell ruby])
    create("out.md", path: "member/scripts", tags: %w[go])

    all = Tools::List.call(server_context: ctx)
    assert_equal "shell  2\ngo  1\nruby  1", text_of(all)
    assert_equal [ { name: "shell", count: 2 }, { name: "go", count: 1 }, { name: "ruby", count: 1 } ], all.to_h[:structuredContent][:tags]

    assert_equal "shell  2\nruby  1", text_of(Tools::List.call(within: "member/notes", server_context: ctx))
    assert_equal "No tags", text_of(Tools::List.call(within: "member/empty", server_context: ctx))
  end
end
