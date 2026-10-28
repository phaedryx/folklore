module SearchEval
  # Measures whether retrieval actually finds things. Runs every query in a YAML file
  # through the current search and through a fixed baseline (every term required,
  # unstemmed, plus a substring match on the name) and reports where the expected asset
  # landed. Rank 1 is best; "--" means it was not in the top K at all.
  #
  # The queries file is a list of `{query:, expect: [slug, ...]}` entries. It names real
  # assets in a real corpus, so it is never committed: pass its path to the rake task,
  # `bin/rails "folklore:search_eval[path/to/queries.yml]"`, or set FOLKLORE_EVAL_QUERIES.
  #
  # The baseline recomputes a plain tsvector per row rather than reading content_tsv,
  # which holds english lexemes. At the corpus sizes this is run against that is fine.
  class Runner
    MissingQueriesError = Class.new(StandardError)

    K = 10

    # Notes that quote the eval queries (a plan, a session checkpoint) match every query
    # perfectly and bury the real answers. They are tagged out of the corpus, not deleted.
    EXCLUDED = %w[eval-excluded].freeze

    def self.call(queries_path, out: $stdout)
      new(queries_path, out:).call
    end

    def initialize(queries_path, out:)
      @queries_path = queries_path
      @out = out
    end

    def call
      rows = cases.map { |kase| row_for(kase["query"], Array(kase["expect"])) }

      @out.puts "corpus: #{Asset.live.count} live assets   queries: #{rows.size}   K: #{K}"
      @out.puts
      @out.puts format("%-46s %-14s %-14s", "query", "baseline", "current")
      @out.puts "-" * 78
      rows.each do |row|
        @out.puts format("%-46s %-14s %-14s", row[:query][0, 45],
                         cell(row[:baseline_rank], row[:baseline_hits]), cell(row[:current_rank], row[:current_hits]))
      end
      @out.puts "-" * 78
      @out.puts "baseline #{summarize(rows, :baseline_rank)}"
      @out.puts "current  #{summarize(rows, :current_rank)}"
    end

    private

    def cases
      path = @queries_path.to_s
      if path.blank? || !File.exist?(path)
        raise MissingQueriesError, "no queries file at #{path.inspect}: pass a path to folklore:search_eval " \
                                   "or set FOLKLORE_EVAL_QUERIES"
      end

      YAML.load_file(path)
    end

    def row_for(query, expected)
      baseline = baseline_results(query)
      current = current_results(query)

      {
        query:,
        baseline_rank: Scorecard.rank_of(baseline.map(&:slug), expected),
        baseline_hits: baseline.size,
        current_rank: Scorecard.rank_of(current.map(&:slug), expected),
        current_hits: current.size
      }
    end

    def excluded_ids
      Asset.joins(:tags).where(tags: { name: EXCLUDED }).select(:id)
    end

    def baseline_results(query)
      Asset.live.where(Asset.sanitize_sql_array([
        "to_tsvector('simple', COALESCE(assets.content, '')) @@ plainto_tsquery('simple', ?) " \
        "OR assets.name ILIKE ?",
        query, "%#{Asset.sanitize_sql_like(query)}%"
      ])).where.not(id: excluded_ids).limit(K).to_a
    end

    def current_results(query)
      Assets::Search.query(query:, exclude_tags: EXCLUDED, limit: K).to_a
    end

    def cell(rank, hits)
      rank ? "##{rank} of #{hits}" : "-- (#{hits} hits)"
    end

    def summarize(rows, key)
      card = Scorecard.new(rows.map { |row| row[key] })
      format("recall@%d %5.1f%%   top-1 %5.1f%%   MRR %.3f", K, card.recall * 100, card.top_1 * 100, card.mrr)
    end
  end
end
