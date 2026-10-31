module SearchEval
  # Measures whether retrieval actually finds things. Runs every query in a YAML file
  # through the current search and through a fixed baseline (every term required,
  # unstemmed, plus a substring match on the name) and reports where the expected asset
  # landed. Rank 1 is best; "--" means it was not in the top K at all.
  #
  # The queries file is a list of `{query:, expect: [slug, ...]}` entries. A file naming your
  # own assets is never committed: pass its path to the rake task,
  # `bin/rails "folklore:search_eval[path/to/queries.yml]"`, or set FOLKLORE_EVAL_QUERIES.
  # With neither, the task runs the committed synthetic set instead (SearchEval::Synthetic).
  #
  # The baseline recomputes a plain tsvector per row rather than reading content_tsv,
  # which holds english lexemes. At the corpus sizes this is run against that is fine.
  class Runner
    MissingQueriesError = Class.new(StandardError)
    UnknownSlugError = Class.new(StandardError)

    K = 10

    # Notes that quote the eval queries (a plan, a session checkpoint) match every query
    # perfectly and bury the real answers. They are tagged out of the corpus, not deleted.
    EXCLUDED = %w[eval-excluded].freeze

    def self.call(queries_path, out: $stdout)
      new(queries_path, out:).call
    end

    # `within` confines the corpus to one directory, as SearchEval::Synthetic does to keep its
    # assets apart from whatever else the database holds.
    def initialize(queries_path, out:, within: nil)
      @queries_path = queries_path
      @out = out
      @within = within
    end

    def call
      check_expected_slugs!
      rows = cases.map { |kase| row_for(kase["query"], Array(kase["expect"])) }

      @out.puts "corpus: #{corpus.count} live assets   queries: #{rows.size}   K: #{K}"
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
      @cases ||= begin
        path = @queries_path.to_s
        if path.blank? || !File.exist?(path)
          raise MissingQueriesError, "no queries file at #{path.inspect}: pass a path to folklore:search_eval " \
                                     "or set FOLKLORE_EVAL_QUERIES"
        end

        YAML.load_file(path)
      end
    end

    # An answer that is not in the corpus can never be found, so a typo in a slug would
    # count as a miss and lower the score without saying why.
    def check_expected_slugs!
      expected = cases.flat_map { |kase| Array(kase["expect"]) }.uniq
      known = corpus.where(slug: expected).pluck(:slug)
      missing = cases.flat_map do |kase|
        (Array(kase["expect"]) - known).map { |slug| "#{kase['query'].inspect} expects #{slug}" }
      end
      return if missing.empty?

      raise UnknownSlugError, "expected slugs not in the corpus (missing, deleted or eval-excluded): " \
                              "#{missing.join('; ')}"
    end

    def corpus
      scope = Asset.live.where.not(id: excluded_ids)
      @within ? scope.under_dir(@within) : scope
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

    # Ordered by its own score, then slug, so the baseline lands the same way on every run.
    def baseline_results(query)
      corpus.where(Asset.sanitize_sql_array([
        "to_tsvector('simple', COALESCE(assets.content, '')) @@ plainto_tsquery('simple', ?) " \
        "OR assets.name ILIKE ?",
        query, "%#{Asset.sanitize_sql_like(query)}%"
      ])).order(Arel.sql(Asset.sanitize_sql_array([
        "ts_rank(to_tsvector('simple', COALESCE(assets.content, '')), plainto_tsquery('simple', ?)) DESC", query
      ])), :slug).limit(K).to_a
    end

    def current_results(query)
      Assets::Search.query(query:, path: @within, exclude_tags: EXCLUDED, limit: K).to_a
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
