require "test_helper"
require "rake"

class FolklorePruneVersionsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @actor = actor_for(:member_default)
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "a.md", content: "v0")
    3.times { |i| Assets::Update.mutate(actor: @actor, slug: @asset.slug, content: "v#{i + 1}") }
  end

  def run_prune(keep)
    Rake::Task["folklore:prune_versions"].reenable
    capture_io { Rake::Task["folklore:prune_versions"].invoke(keep) }
  end

  def refuse_prune(keep)
    Rake::Task["folklore:prune_versions"].reenable
    capture_io { assert_raises(SystemExit) { Rake::Task["folklore:prune_versions"].invoke(keep) } }
  end

  test "keeps each asset's newest versions and prints how many it deleted" do
    out, = run_prune("1")

    assert_match(/Deleted 2 versions, keeping the newest 1 of each asset/, out)
    assert_equal %w[v2], @asset.versions.pluck(:content)
  end

  test "refuses a missing or bad keep and deletes nothing" do
    [ nil, "-1" ].each do |keep|
      _, err = refuse_prune(keep)
      assert_match(/usage|keep must be/, err)
    end

    assert_equal 3, @asset.versions.count
  end
end
