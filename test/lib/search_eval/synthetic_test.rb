require "test_helper"

class SearchEval::SyntheticTest < ActiveSupport::TestCase
  # docs/search.md publishes these numbers. A ranking change that moves them should move
  # the docs with it, so this fails until both agree.
  test "the committed corpus and queries score what docs/search.md says" do
    out = StringIO.new
    SearchEval::Synthetic.call(out:)

    assert_match(/queries: 28/, out.string)
    assert_match(/baseline recall@10  67.9%   top-1  67.9%   MRR 0.679/, out.string)
    assert_match(/current  recall@10  96.4%   top-1  89.3%   MRR 0.917/, out.string)
  end

  test "leaves nothing behind" do
    assert_no_difference -> { Asset.count } do
      assert_no_difference -> { User.count } do
        SearchEval::Synthetic.call(out: StringIO.new)
      end
    end
  end

  # Ranked within its own directory, the corpus scores the same whatever else the database holds.
  test "other assets in the database do not change the result" do
    clean = StringIO.new
    SearchEval::Synthetic.call(out: clean)
    Asset.create!(owner: users(:member), slug: Asset.generate_slug, dir: "member/notes", name: "deploy-rollback.md",
                  content: "how do we roll back a deploy " * 20)

    noisy = StringIO.new
    SearchEval::Synthetic.call(out: noisy)

    assert_equal clean.string, noisy.string
  end
end
