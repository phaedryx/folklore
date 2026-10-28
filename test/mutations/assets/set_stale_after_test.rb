require "test_helper"

class Assets::SetStaleAfterTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "n.md", content: "body")
  end

  def schedule(stale_after, **args)
    Assets::SetStaleAfter.mutate(**{ actor: @actor, slug: @asset.slug, stale_after: }.merge(args))
  end

  test "sets a review date without claiming verification" do
    result = schedule("2026-12-01")

    assert_equal Date.new(2026, 12, 1), result.stale_after
    assert_nil result.verified_at
    assert_nil result.verified_by_agent
  end

  test "leaves an earlier verification intact and clears on empty string" do
    Assets::Verify.mutate(actor: @actor, slug: @asset.slug)
    verified_at = @asset.reload.verified_at

    schedule("2027-01-01")
    assert_equal verified_at.to_i, @asset.reload.verified_at.to_i

    schedule("")
    assert_nil @asset.reload.stale_after
  end

  test "is not an edit: no updated_at bump, an asset_review_scheduled event" do
    before = @asset.updated_at

    travel(1.day) { schedule("2027-01-01") }

    assert_equal before.to_i, @asset.reload.updated_at.to_i
    assert_equal "asset_review_scheduled", Event.where(asset_id: @asset.id).last.action
  end

  test "rejects an unparseable date" do
    assert_raises(Asset::InvalidStaleAfterError) { schedule("soon") }
  end

  test "raises NotFoundError for unknown or deleted, ForbiddenError for another member" do
    assert_raises(Assets::NotFoundError) { schedule("2027-01-01", slug: "00000000") }
    assert_raises(Assets::ForbiddenError) { schedule("2027-01-01", actor: actor_for(:other_default)) }

    @asset.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { schedule("2027-01-01") }
  end
end
