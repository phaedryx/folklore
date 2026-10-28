module SearchEval
  # Retrieval metrics for the search eval runner. A rank is the 1-based position at which
  # a query's expected asset appeared, or nil if it never did.
  class Scorecard
    def initialize(ranks)
      @ranks = ranks
    end

    # Position of the earliest acceptable answer. Several are allowed because a question
    # can have more than one right note.
    def self.rank_of(slugs, expected)
      found = slugs.index { |slug| expected.include?(slug) }
      found && found + 1
    end

    # Share of queries whose answer appeared at all.
    def recall = mean { |rank| rank ? 1.0 : 0.0 }

    # Share of queries whose answer appeared first: the number a person actually feels.
    def top_1 = mean { |rank| rank == 1 ? 1.0 : 0.0 }

    # Mean reciprocal rank: rewards moving an answer from 4th to 2nd, which recall can't see.
    def mrr = mean { |rank| rank ? 1.0 / rank : 0.0 }

    private

    def mean
      return 0.0 if @ranks.empty?

      @ranks.sum { |rank| yield(rank) } / @ranks.size.to_f
    end
  end
end
