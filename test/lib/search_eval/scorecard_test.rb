require "test_helper"

class SearchEval::ScorecardTest < ActiveSupport::TestCase
  test "rank_of is 1-based so the first result scores best" do
    assert_equal 1, SearchEval::Scorecard.rank_of(%w[a b c], %w[a])
  end

  test "rank_of finds the earliest of several acceptable answers" do
    assert_equal 2, SearchEval::Scorecard.rank_of(%w[a b c], %w[c b])
  end

  test "rank_of is nil when no acceptable answer is present" do
    assert_nil SearchEval::Scorecard.rank_of(%w[a b c], %w[z])
  end

  test "a miss contributes nothing to MRR rather than raising" do
    scorecard = SearchEval::Scorecard.new([ 1, nil ])

    assert_in_delta 0.5, scorecard.mrr, 0.0001
  end

  test "MRR is the mean of the reciprocals of each rank" do
    scorecard = SearchEval::Scorecard.new([ 1, 2, 4 ])

    assert_in_delta (1 + 0.5 + 0.25) / 3, scorecard.mrr, 0.0001
  end

  test "recall counts every rank that landed, top-1 only the first place ones" do
    scorecard = SearchEval::Scorecard.new([ 1, 3, nil, nil ])

    assert_in_delta 0.5, scorecard.recall, 0.0001
    assert_in_delta 0.25, scorecard.top_1, 0.0001
  end

  test "an empty scorecard scores zero instead of dividing by zero" do
    scorecard = SearchEval::Scorecard.new([])

    assert_equal 0.0, scorecard.recall
    assert_equal 0.0, scorecard.mrr
  end
end
