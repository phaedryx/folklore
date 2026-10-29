require "test_helper"
require "rake"

class FolkloreImportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @dir = Dir.mktmpdir("bundle-import-task")
    @bundle = BundleWriter.new(@dir)
  end

  teardown do
    FileUtils.rm_rf(@dir)
    ENV.delete("DRY_RUN")
  end

  def run_import
    Rake::Task["folklore:import"].reenable
    capture_io { Rake::Task["folklore:import"].invoke(@dir) }
  end

  test "imports and prints the counts and dangling links" do
    @bundle.asset(name: "a.md", content: "[[qqqqqqqq]]")
    @bundle.write

    out, = run_import

    assert_match(/Imported 1 assets \(0 archived, 0 tasks\) and 0 versions/, out)
    assert_match(%r{member/notes/a.md \(\w+\) -> \[\[qqqqqqqq\]\]}, out)
    assert Asset.live.exists?(name: "a.md")
  end

  test "DRY_RUN writes nothing and says so" do
    @bundle.asset(name: "a.md")
    @bundle.write
    ENV["DRY_RUN"] = "1"

    out, = run_import

    assert_match(/Would import 1 assets .* \(dry run\)/, out)
    refute Asset.exists?(name: "a.md")
  end

  test "a refused bundle lists every problem and exits non-zero" do
    @bundle.asset(owner: "ghost", dir: "ghost/notes", name: "a.md")
    @bundle.write

    error = nil
    _, err = capture_io do
      Rake::Task["folklore:import"].reenable
      error = assert_raises(SystemExit) { Rake::Task["folklore:import"].invoke(@dir) }
    end

    refute error.success?
    assert_match(/Nothing was written/, err)
    assert_match(/owner "ghost" is not a user here/, err)
  end
end
