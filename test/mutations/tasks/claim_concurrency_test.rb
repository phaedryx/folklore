require "test_helper"

# Claims under real contention: threads on separate connections, released
# through a barrier so they reach the database together. Transactional
# fixtures would hide the race, so this case cleans up by hand.
class Tasks::ClaimConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    Event.delete_all
    Task.delete_all
    AssetTag.delete_all
    Link.delete_all
    Version.delete_all
    Asset.delete_all
  end

  def actor(agent)
    Actor.for_token(Token.find(tokens(:member_default).id), agent:)
  end

  def add(name, path: "member/race")
    Tasks::Add.mutate(actor: actor("seeder"), path:, name:, content: "")
  end

  # Runs one block per agent on its own thread, released together.
  def race(agents)
    barrier = Concurrent::CyclicBarrier.new(agents.size)
    agents.map do |agent|
      Thread.new do
        barrier.wait
        yield actor(agent)
      ensure
        ActiveRecord::Base.connection_pool.release_connection
      end
    end.each(&:join)
  end

  test "exactly one of two agents on one token wins a claim by slug" do
    task = add("task.md")
    results = Concurrent::Array.new

    race(%w[ping pong]) do |actor|
      results << [ :ok, Tasks::Claim.mutate(actor:, slug: task.slug).task.claimed_by_agent ]
    rescue Tasks::AlreadyClaimedError
      results << [ :already_claimed, actor.agent ]
    end

    assert_equal [ :already_claimed, :ok ], results.map(&:first).sort, results.inspect
    winner = results.find { |r| r.first == :ok }.last
    task.task.reload
    assert_equal "in_progress", task.task.status
    assert_equal winner, task.task.claimed_by_agent
    assert_equal 1, Event.where(asset_id: task.id, action: "task_claimed").count
  end

  test "two agents claiming the next pending task at once get two different tasks" do
    add("first.md")
    add("second.md")
    claimed = Concurrent::Array.new

    race(%w[ping pong]) do |actor|
      claimed << Tasks::Claim.mutate(actor:, path_prefix: "member/race").name
    end

    assert_equal %w[first.md second.md], claimed.sort, claimed.inspect
    assert_equal %w[ping pong], Task.pluck(:claimed_by_agent).sort
  end

  test "two agents sweeping a backlog in next-pending mode claim every task exactly once" do
    12.times { |i| add(format("t%02d.md", i)) }
    successes = Concurrent::Array.new

    race(%w[ping pong]) do |actor|
      loop do
        successes << [ Tasks::Claim.mutate(actor:, path_prefix: "member/race").id, actor.agent ]
      rescue Tasks::NoPendingTaskError
        break
      end
    end

    assert_equal 12, successes.size, "every task claimed exactly once"
    assert_equal 12, successes.map(&:first).uniq.size, "no task claimed twice"
    Task.includes(:asset).find_each do |task|
      assert_equal "in_progress", task.status
      assert_equal successes.find { |id, _| id == task.asset_id }.last, task.claimed_by_agent
    end
  end

  # The same race through the claim_task tool agents actually call, so the
  # tool's error mapping is proven under contention too.
  test "two agents racing through claim_task produce one win and one already-claimed" do
    task = add("tool.md")
    responses = Concurrent::Array.new

    race(%w[ping pong]) do |actor|
      responses << FolkloreMcp::Tools::Tasks::Claim.call(slug: task.slug, server_context: { actor: }).to_h
    end

    errors, oks = responses.partition { |r| r[:isError] }
    assert_equal 1, oks.size, responses.inspect
    assert_equal 1, errors.size, responses.inspect
    assert_match(/\AAlready claimed \[[a-z_]+\]: /, errors.first[:content].first[:text])
  end
end
