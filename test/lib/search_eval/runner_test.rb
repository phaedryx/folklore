require "test_helper"

class SearchEval::RunnerTest < ActiveSupport::TestCase
  def build(name, content:, tags: [])
    asset = Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name:, content:)
    tags.each { |tag| AssetTag.create!(asset:, tag: Tag.find_or_create_by!(name: tag)) }
    asset
  end

  def queries_file(cases)
    path = Rails.root.join("tmp/search_eval_#{SecureRandom.hex(4)}.yml")
    path.write(cases.to_yaml)
    path
  end

  teardown do
    Rails.root.glob("tmp/search_eval_*.yml").each(&:delete)
  end

  test "reports where each expected asset landed and the summary metrics" do
    hit = build("cavoodle.md", content: "we chose a cavoodle for the family dog")
    build("django.md", content: "python django")
    path = queries_file([ { "query" => "cavoodle dog", "expect" => [ hit.slug ] },
                          { "query" => "nothing matches this", "expect" => [ "zzzzzzzz" ] } ])

    out = StringIO.new
    SearchEval::Runner.call(path, out:)

    assert_match(/queries: 2/, out.string)
    assert_match(/cavoodle dog\s+.*#1 of 1/, out.string)
    assert_match(/current\s+recall@10\s+50\.0%\s+top-1\s+50\.0%\s+MRR 0\.500/, out.string)
  end

  test "assets tagged eval-excluded are left out of the corpus" do
    build("answers.md", content: "cavoodle dog cavoodle dog cavoodle dog", tags: %w[eval-excluded])
    hit = build("real.md", content: "a cavoodle is a dog")
    path = queries_file([ { "query" => "cavoodle dog", "expect" => [ hit.slug ] } ])

    out = StringIO.new
    SearchEval::Runner.call(path, out:)

    assert_match(/#1 of 1/, out.string)
  end

  test "a missing queries file is a clear error, not a stack trace" do
    error = assert_raises(SearchEval::Runner::MissingQueriesError) do
      SearchEval::Runner.call(Rails.root.join("tmp/does-not-exist.yml"), out: StringIO.new)
    end

    assert_match(/FOLKLORE_EVAL_QUERIES/, error.message)
  end

  test "the rake task takes the queries path from its argument" do
    require "rake"
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    hit = build("cavoodle.md", content: "we chose a cavoodle")
    path = queries_file([ { "query" => "cavoodle", "expect" => [ hit.slug ] } ])

    Rake::Task["folklore:search_eval"].reenable
    out, = capture_io { Rake::Task["folklore:search_eval"].invoke(path.to_s) }

    assert_match(/queries: 1/, out)
  end
end
