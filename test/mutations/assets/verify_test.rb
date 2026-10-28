require "test_helper"

class Assets::VerifyTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "n.md", content: "body")
  end

  def verify(**args)
    Assets::Verify.mutate(**{ actor: @actor, slug: @asset.slug }.merge(args))
  end

  test "records who verified and when" do
    result = verify

    assert_not_nil result.verified_at
    assert_equal tokens(:member_default), result.verified_by_token
    assert_equal "ping", result.verified_by_agent
  end

  test "sets stale_after from an ISO date, leaves it alone when omitted, clears it on empty string" do
    assert_equal Date.new(2026, 12, 1), verify(stale_after: "2026-12-01").stale_after
    assert_equal Date.new(2026, 12, 1), verify.stale_after
    assert_nil verify(stale_after: "").stale_after
  end

  test "re-verifying moves verified_at forward" do
    first = verify.verified_at

    travel(1.day) { verify }

    assert @asset.reload.verified_at > first
  end

  test "is not an edit: no updated_at bump, no version, no updated_by change, an asset_verified event" do
    before = @asset.updated_at

    travel(1.day) { verify(stale_after: "2027-01-01") }

    @asset.reload
    assert_equal before.to_i, @asset.updated_at.to_i
    assert_equal 0, @asset.versions.count
    assert_nil @asset.updated_by_agent
    assert_equal "asset_verified", Event.where(asset_id: @asset.id).last.action
  end

  test "rejects an unparseable stale_after" do
    assert_raises(Asset::InvalidStaleAfterError) { verify(stale_after: "next tuesday") }
  end

  test "raises NotFoundError for unknown or deleted, ForbiddenError for another member" do
    assert_raises(Assets::NotFoundError) { verify(slug: "00000000") }
    assert_raises(Assets::ForbiddenError) { verify(actor: actor_for(:other_default)) }

    @asset.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { verify }
  end
end
