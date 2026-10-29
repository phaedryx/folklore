require "test_helper"
require "rake"

class FolkloreExportTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @dir = Dir.mktmpdir("bundle-export-task")
  end

  teardown do
    FileUtils.rm_rf(@dir)
    ENV.delete("HANDLE")
  end

  def run_export(path)
    Rake::Task["folklore:export"].reenable
    capture_io { Rake::Task["folklore:export"].invoke(path) }
  end

  test "writes a bundle and prints its counts" do
    Assets::Create.mutate(actor: actor_for(:member_default), path: "member/notes", name: "a.md", content: "x")
    Assets::Create.mutate(actor: actor_for(:other_default), path: "other/notes", name: "b.md", content: "y")
    ENV["HANDLE"] = "member"

    out, = run_export(File.join(@dir, "out"))

    assert_match(/Exported 1 assets \(0 archived, 0 tasks\) and 0 versions/, out)
    assert File.exist?(File.join(@dir, "out/assets/member/notes/a.md"))
    refute File.exist?(File.join(@dir, "out/assets/other/notes/b.md"))
  end

  test "exits non-zero on a non-empty directory" do
    File.write(File.join(@dir, "stray"), "x")

    error = assert_raises(SystemExit) { run_export(@dir) }
    refute error.success?
  end
end
