require "test_helper"

class SearchLogs::PruneTest < ActiveSupport::TestCase
  def log(created_at)
    SearchLog.create!(query: "cavoodle", created_at:)
  end

  test "deletes logs older than the cutoff and keeps the rest" do
    old = log(200.days.ago)
    recent = log(10.days.ago)

    deleted = SearchLogs::Prune.mutate(older_than: 180.days)

    assert_equal 1, deleted
    assert_not SearchLog.exists?(old.id)
    assert SearchLog.exists?(recent.id)
  end

  test "keeps 180 days by default" do
    log(181.days.ago)
    kept = log(179.days.ago)

    SearchLogs::Prune.mutate

    assert_equal [ kept ], SearchLog.all.to_a
  end

  test "a cutoff of zero or less is refused rather than emptying the table" do
    log(1.day.ago)

    assert_raises(ArgumentError) { SearchLogs::Prune.mutate(older_than: 0.days) }
    assert_equal 1, SearchLog.count
  end
end
