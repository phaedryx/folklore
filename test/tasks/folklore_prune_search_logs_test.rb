require "test_helper"
require "rake"

class FolklorePruneSearchLogsTaskTest < ActiveSupport::TestCase
  setup { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def run_prune(*args)
    Rake::Task["folklore:prune_search_logs"].reenable
    capture_io { Rake::Task["folklore:prune_search_logs"].invoke(*args) }
  end

  test "takes the retention in days from its argument and reports what it deleted" do
    SearchLog.create!(query: "old", created_at: 40.days.ago)
    SearchLog.create!(query: "new", created_at: 10.days.ago)

    out, = run_prune("30")

    assert_match(/Deleted 1 search log older than 30 days/, out)
    assert_equal %w[new], SearchLog.pluck(:query)
  end

  test "exits non-zero on a retention that is not a positive number of days" do
    error = assert_raises(SystemExit) { run_prune("zero") }
    refute error.success?
  end
end
