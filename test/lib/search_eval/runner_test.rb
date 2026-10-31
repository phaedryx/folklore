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
    (@written ||= []) << path
    path
  end

  # Only this test's files: parallel workers share tmp/, so a glob here
  # deleted another worker's queries file mid-run.
  teardown do
    Array(@written).each { |path| path.delete if path.exist? }
  end

  test "reports where each expected asset landed and the summary metrics" do
    hit = build("cavoodle.md", content: "we chose a cavoodle for the family dog")
    unfound = build("django.md", content: "python django")
    path = queries_file([ { "query" => "cavoodle dog", "expect" => [ hit.slug ] },
                          { "query" => "nothing matches this", "expect" => [ unfound.slug ] } ])

    out = StringIO.new
    SearchEval::Runner.call(path, out:)

    assert_match(/queries: 2/, out.string)
    assert_match(/cavoodle dog\s+.*#1 of 1/, out.string)
    assert_match(/current\s+recall@10\s+50\.0%\s+top-1\s+50\.0%\s+MRR 0\.500/, out.string)
  end

  # A typo in an expected slug used to read as a miss, lowering the score without a word.
  test "an expected slug that is not in the corpus is an error naming it" do
    hit = build("cavoodle.md", content: "we chose a cavoodle")
    path = queries_file([ { "query" => "cavoodle", "expect" => [ hit.slug ] },
                          { "query" => "dog breed", "expect" => [ "zzzzzzzz" ] } ])

    error = assert_raises(SearchEval::Runner::UnknownSlugError) { SearchEval::Runner.call(path, out: StringIO.new) }

    assert_match(/"dog breed".*zzzzzzzz/, error.message)
  end

  test "an expected slug that is eval-excluded is not in the corpus either" do
    hidden = build("answers.md", content: "cavoodle", tags: %w[eval-excluded])
    path = queries_file([ { "query" => "cavoodle", "expect" => [ hidden.slug ] } ])

    assert_raises(SearchEval::Runner::UnknownSlugError) { SearchEval::Runner.call(path, out: StringIO.new) }
  end

  # The baseline had no ORDER BY, so where its answer landed was up to the planner. It now
  # ranks by its own score and breaks ties by slug, so two runs over one corpus agree.
  test "the baseline ranks its matches by its own score, then by slug" do
    Asset.create!(owner: users(:member), slug: "bbbbbbbb", dir: "member/notes", name: "b.md", content: "cavoodle")
    Asset.create!(owner: users(:member), slug: "aaaaaaaa", dir: "member/notes", name: "a.md", content: "cavoodle")
    strong = build("strong.md", content: "cavoodle cavoodle cavoodle")
    path = queries_file([ { "query" => "cavoodle", "expect" => [ strong.slug ] },
                          { "query" => "cavoodle", "expect" => [ "aaaaaaaa" ] } ])

    out = StringIO.new
    SearchEval::Runner.call(path, out:)

    rows = out.string.lines.grep(/\Acavoodle/)
    assert_match(/\Acavoodle\s+#1 of 3/, rows[0])
    assert_match(/\Acavoodle\s+#2 of 3/, rows[1])
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

  test "the rake task with no queries file runs the committed synthetic eval" do
    require "rake"
    Rails.application.load_tasks if Rake::Task.tasks.empty?

    Rake::Task["folklore:search_eval"].reenable
    out, = capture_io { Rake::Task["folklore:search_eval"].invoke }

    assert_match(/synthetic corpus/, out)
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
