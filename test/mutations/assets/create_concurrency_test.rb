require "test_helper"

# Two writers racing for one (dir, name): the partial unique index decides,
# and the loser gets NameTakenError rather than a second live asset.
class Assets::CreateConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    Event.delete_all
    AssetTag.delete_all
    Link.delete_all
    Version.delete_all
    Asset.delete_all
  end

  test "exactly one of two concurrent creates of the same name wins" do
    results = Concurrent::Array.new
    barrier = Concurrent::CyclicBarrier.new(2)

    2.times.map do |i|
      Thread.new do
        actor = Actor.for_token(Token.find(tokens(:member_default).id), agent: "writer#{i}")
        barrier.wait
        begin
          results << [ :ok, Assets::Create.mutate(actor:, path: "member/race", name: "same.md", content: i.to_s).id ]
        rescue Assets::Create::NameTakenError
          results << [ :name_taken, i ]
        ensure
          ActiveRecord::Base.connection_pool.release_connection
        end
      end
    end.each(&:join)

    assert_equal [ :name_taken, :ok ], results.map(&:first).sort, results.inspect
    assert_equal 1, Asset.live.where(dir: "member/race", name: "same.md").count
    assert_equal 1, Event.where(action: "asset_created").count
  end
end
