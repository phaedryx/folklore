require "test_helper"

class Assets::BulkReadTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @first = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "a.md", content: "aaaa")
    @second = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "b.md", content: "bbbb")
  end

  test "reads by slug and by location, in request order" do
    result = Assets::BulkRead.query(slugs: [ @first.slug ], locations: [ "member/notes/b.md" ], actor: @actor)

    assert_equal [ @first, @second ], result.items.map(&:asset)
    assert_equal [ @first.slug, "member/notes/b.md" ], result.items.map(&:key)
    assert_equal 8, result.bytes_returned
    refute result.truncated
  end

  test "records not_found and invalid locations without aborting the batch" do
    result = Assets::BulkRead.query(slugs: [ @first.slug, "00000000" ], locations: [ "nope" ], actor: @actor)

    assert_nil result.items[0].error
    assert_equal "not_found", result.items[1].error
    assert_match(/location/, result.items[2].error)
  end

  test "omits content once max_bytes is exceeded" do
    result = Assets::BulkRead.query(locations: [ "member/notes/a.md", "member/notes/b.md" ], max_bytes: 4, actor: @actor)

    assert result.truncated
    refute result.items[0].content_omitted
    assert result.items[1].content_omitted
    assert_equal 4, result.bytes_returned
  end

  test "include_content: false counts no bytes" do
    result = Assets::BulkRead.query(slugs: [ @first.slug ], include_content: false, actor: @actor)

    assert_equal 0, result.bytes_returned
    refute result.items[0].content_omitted
  end
end
