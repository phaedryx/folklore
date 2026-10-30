require "test_helper"

# The first uses of a tag nobody has used yet race to insert its tags row.
# The loser must use the winner's row: a tag that exists by the time the
# write lands is not an error. Each test lets another connection commit the
# tag in the gap between the writer's lookup missing and its insert.
class Tags::ApplyConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    Event.delete_all
    AssetTag.delete_all
    Tag.delete_all
    Link.delete_all
    Version.delete_all
    Asset.delete_all
  end

  test "add_tag of a tag another writer commits at the same moment succeeds" do
    asset = Assets::Create.mutate(actor: actor_for(:member_default), path: "member/race", name: "a.md", content: "")

    once_the_lookup_misses_another_writer_commits("brand-new") do
      Tags::Apply.mutate(actor: actor_for(:member_default), slug: asset.slug, tag: "brand-new")
    end

    assert_equal %w[brand-new], asset.reload.tags.pluck(:name)
  end

  test "create carrying a tag another writer commits at the same moment succeeds" do
    asset = once_the_lookup_misses_another_writer_commits("brand-new") do
      Assets::Create.mutate(actor: actor_for(:member_default), path: "member/race", name: "a.md", content: "", tags: [ "brand-new" ])
    end

    assert_equal %w[brand-new], asset.reload.tags.pluck(:name)
  end

  test "update adding a tag another writer commits at the same moment succeeds" do
    asset = Assets::Create.mutate(actor: actor_for(:member_default), path: "member/race", name: "a.md", content: "")

    once_the_lookup_misses_another_writer_commits("brand-new") do
      Assets::Update.mutate(actor: actor_for(:member_default), slug: asset.slug, tags: [ "brand-new" ])
    end

    assert_equal %w[brand-new], asset.reload.tags.pluck(:name)
  end

  private

  # Another connection inserts the tag and holds its transaction open, then
  # commits at the first point the block can race it: just after the block
  # looks the tag up and misses, or just as the block starts inserting it.
  def once_the_lookup_misses_another_writer_commits(name)
    inserted = Concurrent::Event.new
    commit = Concurrent::Event.new
    other = Thread.new do
      ActiveRecord::Base.transaction do
        Tag.create!(name:)
        inserted.set
        commit.wait(5)
      end
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end
    inserted.wait(5)

    hook = CommitAt.new(Thread.current, commit, other)
    result = ActiveSupport::Notifications.subscribed(hook, "sql.active_record") { yield }
    assert hook.released?, "the block never looked up or inserted the tag, so the race was not set up"
    result
  ensure
    commit&.set
    other&.join
  end

  # A subscriber with start and finish hooks: an INSERT is caught before it
  # runs (it would wait on the held row), a SELECT after it has missed.
  class CommitAt
    def initialize(writer, commit, other)
      @writer = writer
      @commit = commit
      @other = other
      @released = false
    end

    def released? = @released

    def start(_name, _id, payload)
      release if payload[:sql].start_with?('INSERT INTO "tags"')
    end

    def finish(_name, _id, payload)
      release if payload[:sql].match?(/\ASELECT .* FROM "tags" WHERE "tags"."name"/)
    end

    private

    def release
      return unless Thread.current == @writer && !@commit.set?

      @released = true
      @commit.set
      @other.join
    end
  end
end
