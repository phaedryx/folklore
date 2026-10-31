require "test_helper"

class Assets::BulkReadTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @first = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "a.md", content: "aaaa")
    @second = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "b.md", content: "bbbb")
  end

  test "reads slugs and locations, in request order" do
    result = Assets::BulkRead.query(refs: [ @first.slug, "member/notes/b.md" ], actor: @actor)

    assert_equal [ @first, @second ], result.items.map(&:asset)
    assert_equal [ @first.slug, "member/notes/b.md" ], result.items.map(&:ref)
    assert_equal 8, result.bytes_returned
    refute result.truncated
  end

  test "keeps the error for a missing slug or a bad location without aborting the batch" do
    result = Assets::BulkRead.query(refs: [ @first.slug, "00000000", "member/" ], actor: @actor)

    assert_nil result.items[0].error
    assert_kind_of Assets::NotFoundError, result.items[1].error
    assert_kind_of Assets::InvalidLocationError, result.items[2].error
  end

  test "omits content once max_bytes is exceeded" do
    result = Assets::BulkRead.query(refs: [ "member/notes/a.md", "member/notes/b.md" ], max_bytes: 4, actor: @actor)

    assert result.truncated
    refute result.items[0].content_omitted
    assert result.items[1].content_omitted
    assert_equal 4, result.bytes_returned
  end

  test "max_bytes is capped" do
    big = Array.new(2) { |i| Assets::Create.mutate(actor: @actor, path: "member/notes", name: "big#{i}.md", content: "x" * 600_000) }

    result = Assets::BulkRead.query(refs: big.map(&:slug), max_bytes: 10 * Assets::BulkRead::MAX_BYTES, actor: @actor)

    assert result.truncated
    assert_equal 600_000, result.bytes_returned
  end

  test "include_content: false counts no bytes" do
    result = Assets::BulkRead.query(refs: [ @first.slug ], include_content: false, actor: @actor)

    assert_equal 0, result.bytes_returned
    refute result.items[0].content_omitted
  end

  test "refuses no refs or too many" do
    assert_raises(Assets::BulkRead::InvalidArgumentError) { Assets::BulkRead.query(refs: [], actor: @actor) }

    error = assert_raises(Assets::BulkRead::InvalidArgumentError) do
      Assets::BulkRead.query(refs: Array.new(Assets::BulkRead::MAX_REFS + 1, @first.slug), actor: @actor)
    end
    assert_equal "read takes at most #{Assets::BulkRead::MAX_REFS} refs, got #{Assets::BulkRead::MAX_REFS + 1}", error.message
  end
end
