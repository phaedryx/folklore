require "test_helper"

# Two writers on one asset: the row lock serialises them, so each snapshots
# what it actually overwrote and neither update is lost silently.
class Assets::UpdateConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    Event.delete_all
    AssetTag.delete_all
    Link.delete_all
    Version.delete_all
    Asset.delete_all
  end

  test "concurrent updates each produce a version and the final content is one of the two" do
    actor = Actor.for_token(Token.find(tokens(:member_default).id))
    asset = Assets::Create.mutate(actor:, path: "member/race", name: "one.md", content: "v0")
    barrier = Concurrent::CyclicBarrier.new(2)

    %w[alpha beta].map do |content|
      Thread.new do
        barrier.wait
        Assets::Update.mutate(actor:, slug: asset.slug, content:)
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end.each(&:join)

    asset.reload
    assert_includes %w[alpha beta], asset.content
    assert_equal 2, asset.lock_version
    assert_equal [ "v0", (%w[alpha beta] - [ asset.content ]).first ], asset.versions.order(:created_at).map(&:content)
  end
end
