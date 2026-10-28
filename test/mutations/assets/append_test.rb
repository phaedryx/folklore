require "test_helper"

class Assets::AppendTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def log(content)
    Assets::Create.mutate(actor: @actor, path: "member/notes", name: "log.md", content:)
  end

  test "appends after a newline, adding one only when the content lacks it" do
    a = log("line 1")
    Assets::Append.mutate(actor: @actor, slug: a.slug, text: "line 2")
    assert_equal "line 1\nline 2", a.reload.content

    a.update!(content: "line 1\n")
    Assets::Append.mutate(actor: @actor, slug: a.slug, text: "line 2")
    assert_equal "line 1\nline 2", a.reload.content
  end

  test "appends without a leading newline when the content is empty or nil" do
    a = log("")
    Assets::Append.mutate(actor: @actor, slug: a.slug, text: "line 1")
    assert_equal "line 1", a.reload.content

    b = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "nil.md", content: nil)
    Assets::Append.mutate(actor: @actor, slug: b.slug, text: "line 1")
    assert_equal "line 1", b.reload.content
  end

  test "snapshots the prior content and writes an asset_updated event" do
    a = log("original")

    Assets::Append.mutate(actor: @actor, slug: a.slug, text: "more")

    assert_equal [ "original" ], a.versions.map(&:content)
    assert Event.exists?(action: "asset_updated", asset: a)
  end

  test "refuses to grow past the content cap" do
    a = log("x" * (Asset::MAX_CONTENT_BYTES - 2))

    assert_raises(Asset::ContentTooLargeError) { Assets::Append.mutate(actor: @actor, slug: a.slug, text: "yy") }
    assert_equal 0, a.versions.count
  end

  test "raises NotFoundError for an unknown or deleted slug, ForbiddenError for another member" do
    a = log("x")
    assert_raises(Assets::NotFoundError) { Assets::Append.mutate(actor: @actor, slug: "00000000", text: "y") }
    assert_raises(Assets::ForbiddenError) { Assets::Append.mutate(actor: actor_for(:other_default), slug: a.slug, text: "y") }

    a.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { Assets::Append.mutate(actor: @actor, slug: a.slug, text: "y") }
  end
end
