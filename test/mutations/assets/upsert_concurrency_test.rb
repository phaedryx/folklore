require "test_helper"

# Two agents upserting one new location at once: upsert is create-or-update,
# so the loser of the create race must update rather than report a conflict.
class Assets::UpsertConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    Event.delete_all
    AssetTag.delete_all
    Link.delete_all
    Version.delete_all
    Asset.delete_all
  end

  test "concurrent upserts of a new location both succeed: one creates, one updates" do
    actor = Actor.for_token(Token.find(tokens(:member_default).id))
    barrier = Concurrent::CyclicBarrier.new(2)
    results = Concurrent::Array.new

    %w[alpha beta].map do |content|
      Thread.new do
        barrier.wait
        results << Assets::Upsert.mutate(actor:, path: "member/race", name: "same.md", content:)
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end.each(&:join)

    assert_equal [ false, true ], results.map(&:created).sort_by { |c| c ? 1 : 0 }, results.inspect
    assert_equal 1, results.map { |r| r.asset.id }.uniq.size
    asset = Asset.live.find_by!(dir: "member/race", name: "same.md")
    assert_includes %w[alpha beta], asset.content
    assert_equal 1, asset.versions.count
  end

  test "create inside an outer transaction leaves it usable after a name conflict" do
    actor = Actor.for_token(Token.find(tokens(:member_default).id))
    Assets::Create.mutate(actor:, path: "member/race", name: "taken.md")

    ActiveRecord::Base.transaction do
      assert_raises(Assets::NameTakenError) { Assets::Create.mutate(actor:, path: "member/race", name: "taken.md") }
      assert_equal 1, Asset.where(dir: "member/race").count, "the outer transaction still works"
    end
  end
end
