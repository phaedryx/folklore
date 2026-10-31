require "test_helper"

# Writers racing on one asset, or on two assets that link to each other. Each
# test holds a transaction open on purpose, so the overlap is certain rather
# than left to thread scheduling.
class Assets::UpdateConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  # How long a writer may take to reach the row lock before the test gives up.
  BLOCK_TIMEOUT = 5

  teardown do
    # A test that failed mid-race leaves its holder waiting for release and
    # its writers running. Finish them before deleting what they would write.
    @releases&.each(&:set)
    waiting do
      @threads&.each do |thread|
        thread.join(BLOCK_TIMEOUT)
      rescue StandardError
        # Already reported by the test it failed.
      end
    end
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

  # The event a holder waits on before committing. Teardown sets it, so a
  # failed test never leaves a holder open.
  def release_event
    Concurrent::Event.new.tap { |event| (@releases ||= []) << event }
  end

  def backend_pid
    ActiveRecord::Base.lease_connection.select_value("SELECT pg_backend_pid()")
  end

  # Returns once some backend is waiting on a lock held by `holder_pid`, so the
  # race is certain to have happened rather than given time to happen. Keyed
  # on the holder because parallel test workers share the server; uncached
  # because the test runs inside the executor's query cache.
  def wait_until_blocked_by(holder_pid, waiter)
    sql = "SELECT count(*) FROM pg_stat_activity WHERE #{Integer(holder_pid)} = ANY(pg_blocking_pids(pid))"
    deadline = BLOCK_TIMEOUT.seconds.from_now
    waiting do
      until ActiveRecord::Base.uncached { ActiveRecord::Base.lease_connection.select_value(sql) }.positive?
        flunk "no writer blocked on the held row lock" if !waiter.alive? || Time.current > deadline
        sleep 0.01
      end
    end
  end

  def thread(&block)
    Thread.new do
      block.call
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end.tap { |thread| (@threads ||= []) << thread }
  end

  test "a second update waits for the first and snapshots what the first wrote" do
    asset = create("one.md", "v0")
    first_written = Concurrent::Event.new
    release = release_event
    first_pid = nil

    first = thread do
      ActiveRecord::Base.transaction do
        Assets::Update.mutate(actor:, slug: asset.slug, content: "alpha")
        first_pid = backend_pid
        first_written.set
        release.wait(5)
      end
    end
    waiting { first_written.wait(5) }
    second = thread { Assets::Update.mutate(actor:, slug: asset.slug, content: "beta") }

    wait_until_blocked_by(first_pid, second)
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
    release = release_event
    deleter_pid = nil
    outcome = nil

    deleter = thread do
      ActiveRecord::Base.transaction do
        Assets::Delete.mutate(actor:, slug: asset.slug)
        deleter_pid = backend_pid
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

    wait_until_blocked_by(deleter_pid, updater)
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
