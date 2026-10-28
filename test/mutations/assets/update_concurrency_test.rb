require "test_helper"

# Writers racing on one asset, or on two assets that link to each other. Each
# test holds a transaction open on purpose, so the overlap is certain rather
# than left to thread scheduling.
class Assets::UpdateConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # Long enough for a writer that should be waiting on a row lock to have
  # finished if it is not waiting.
  BLOCKED_FOR = 0.3

  teardown do
    Event.delete_all
    AssetTag.delete_all
    Link.delete_all
    Version.delete_all
    Asset.delete_all
  end

  def actor
    @actor ||= Actor.for_token(Token.find(tokens(:member_default).id))
  end

  def create(name, content)
    Assets::Create.mutate(actor:, path: "member/race", name:, content:)
  end

  # The main thread blocks while workers may autoload a constant; letting
  # loads through while it waits keeps the two from deadlocking on Rails'
  # load interlock.
  def waiting(&block)
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads(&block)
  end

  def thread(&block)
    Thread.new do
      block.call
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end
  end

  test "a second update waits for the first and snapshots what the first wrote" do
    asset = create("one.md", "v0")
    first_written = Concurrent::Event.new
    release = Concurrent::Event.new

    first = thread do
      ActiveRecord::Base.transaction do
        Assets::Update.mutate(actor:, slug: asset.slug, content: "alpha")
        first_written.set
        release.wait(5)
      end
    end
    waiting { first_written.wait(5) }
    second = thread { Assets::Update.mutate(actor:, slug: asset.slug, content: "beta") }

    waiting { sleep BLOCKED_FOR }
    assert second.alive?, "the second update did not wait for the first one's row lock"
    release.set
    waiting { [ first, second ].each(&:join) }

    asset.reload
    assert_equal "beta", asset.content
    assert_equal 2, asset.lock_version
    assert_equal %w[v0 alpha], asset.versions.order(:created_at).map(&:content)
  end

  test "an update waiting on a delete does not write into the tombstone" do
    asset = create("doomed.md", "before")
    deleted = Concurrent::Event.new
    release = Concurrent::Event.new
    outcome = nil

    deleter = thread do
      ActiveRecord::Base.transaction do
        Assets::Delete.mutate(actor:, slug: asset.slug)
        deleted.set
        release.wait(5)
      end
    end
    waiting { deleted.wait(5) }
    updater = thread do
      Assets::Update.mutate(actor:, slug: asset.slug, content: "after delete")
      outcome = :updated
    rescue Assets::NotFoundError
      outcome = :not_found
    end

    waiting { sleep BLOCKED_FOR }
    release.set
    waiting { [ deleter, updater ].each(&:join) }

    asset.reload
    assert_equal :not_found, outcome
    assert asset.deleted_at?
    assert_equal "before", asset.content
    assert_empty asset.versions
    assert_equal %w[asset_created asset_deleted], Event.where(asset:).order(:id).pluck(:action)
  end

  test "two assets updated at once to link to each other do not deadlock" do
    a = create("a.md", "a")
    b = create("b.md", "b")
    both_locked = Concurrent::CyclicBarrier.new(2)
    errors = Queue.new

    threads = [ [ a, b ], [ b, a ] ].map do |src, dst|
      thread do
        ActiveRecord::Base.transaction do
          # Each holds its own row before either writes its link, the
          # interleaving that deadlocked when writers took FOR UPDATE.
          Asset.lock(Asset::WRITE_LOCK).find(src.id)
          both_locked.wait(5)
          Assets::Update.mutate(actor:, slug: src.slug, content: "see [[#{dst.slug}]]")
        end
      rescue => e
        errors << e
      end
    end
    waiting { threads.each(&:join) }

    assert_empty Array.new(errors.size) { errors.pop.class }
    assert_equal [ b.id ], Link.where(src_asset: a).pluck(:dst_asset_id)
    assert_equal [ a.id ], Link.where(src_asset: b).pluck(:dst_asset_id)
  end
end
