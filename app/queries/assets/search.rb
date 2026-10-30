module Assets
  class Search
    InvalidArgumentError = Class.new(ArgumentError)

    SORT_COLUMNS = %w[name created_at updated_at].freeze
    MAX_LIMIT = 500

    # word_similarity finds the best-matching run of trigrams inside the name, so a
    # query is compared against part of a filename rather than the whole of it:
    # "deploy" and the typo "deploymnet" both clear this against "deployment-guide.md",
    # while an unrelated query scores 0.
    #
    # 0.5 was too strict: a filename restating the whole query in a different order
    # scored 0.475. Swept against the eval set: 0.45 and 0.47 tie for best (recall@10
    # 94.7%, top-1 84.2%), 0.55 and above lose recall, and below 0.40 top-1 decays as
    # weak name matches start outranking real ones. 0.45 sits at the wide end of that
    # plateau. Note the gain rests on one query, so trust the direction more than the
    # third decimal place.
    NAME_SIMILARITY_THRESHOLD = 0.45

    # websearch_to_tsquery ANDs the terms it produces. Rewriting the operator ORs them,
    # which is how a query is widened when every-term matching comes back empty.
    ALL_TERMS = "websearch_to_tsquery('english', ?)".freeze
    ANY_TERM  = "replace(#{ALL_TERMS}::text, '&', '|')::tsquery".freeze

    # Reciprocal rank fusion constant. Results are insensitive to it (10 and 60 score
    # identically on the eval set) because it only damps how steeply the top of each
    # list is favoured, and both lists are short.
    RRF_K = 60

    def self.query(query:, path: nil, tags: [], status: nil, task_status: nil, stale: nil, exclude_tags: [],
                   sort: nil, limit: nil, offset: 0, include_versions: false, actor: nil)
      new(query:, path:, tags:, status:, task_status:, stale:, exclude_tags:, sort:, limit:, offset:,
          include_versions:, actor:).query
    end

    # Every member reads every workspace, so the actor does not narrow the scope yet; it
    # is accepted now so callers are already passing it when private workspaces arrive.
    def initialize(query:, path:, tags:, status: nil, task_status: nil, stale: nil, exclude_tags: [], sort: nil,
                   limit: nil, offset: 0, include_versions: false, actor: nil)
      @query            = query
      @path             = path
      @tags             = Array(tags)
      @status           = status
      @task_status      = task_status
      @stale            = stale
      @exclude_tags     = Array(exclude_tags)
      @sort             = sort
      @limit            = limit
      @offset           = offset
      @include_versions = include_versions
      @actor            = actor
      validate_pagination!
    end

    # Requiring every term is precise but brittle: one incidental word the author never
    # used ("what dog breed did we _pick_") drops the result set to nothing. Widening to
    # any-term only once that has happened recovers those queries without diluting the
    # ones that were already answered. Widening unconditionally costs more precision
    # than it buys in recall.
    #
    # A negated term never widens: "kubernetes -cluster" parses to kubernet & !cluster, and
    # ORing that would match everything that lacks the word, which is the whole corpus.
    def query
      return finish(filtered, ALL_TERMS) if @query.blank?

      strict = filtered(ALL_TERMS)
      return finish(strict, ALL_TERMS) if strict.exists? || negated?

      finish(filtered(ANY_TERM), ANY_TERM)
    end

    private

    def validate_pagination!
      if @limit.present? && !(1..MAX_LIMIT).cover?(@limit.to_i)
        raise InvalidArgumentError, "limit must be between 1 and #{MAX_LIMIT}, got #{@limit.inspect}"
      end
      if @offset.present? && @offset.to_i.negative?
        raise InvalidArgumentError, "offset cannot be negative, got #{@offset.inspect}"
      end
    end

    def negated?
      Asset.connection.select_value(Asset.sanitize_sql_array([ "SELECT #{ALL_TERMS}::text", @query ])).to_s.include?("!")
    end

    def filtered(tsquery = nil)
      @query.present? ? filters.where(match_condition(tsquery)) : filters
    end

    # Everything that narrows the result set except the query itself. The fused ranking is
    # computed over this too, so a scoped search is ranked within its scope.
    def filters
      scope = Asset.live
      scope = scope.under_dir(@path) if @path.present?

      scope = scope.tagged_with(@tags)

      # `status` matches a note's status or a task's lifecycle state, as one
      # field did before tasks became a facet; `task_status` matches tasks only.
      if @status.present?
        scope = scope.where(status: @status).or(scope.where(id: Task.where(status: @status).select(:asset_id)))
      end

      # A subquery rather than a join: the fused ranking embeds this scope's SQL inside the
      # outer query, and a join of tasks on both sides makes Rails alias the outer one.
      scope = scope.where(id: Task.where(status: @task_status).select(:asset_id)) if @task_status.present?

      scope = @stale ? scope.stale : scope.not_stale unless @stale.nil?

      @exclude_tags.each do |name|
        tag = Tag.find_by(name: name.downcase.strip)
        next unless tag
        scope = scope.where.not(id: AssetTag.where(tag_id: tag.id).select(:asset_id))
      end

      scope
    end

    def finish(scope, tsquery)
      apply_pagination(apply_sort(scope, tsquery))
    end

    def match_condition(tsquery)
      "(#{content_condition(tsquery)}) OR (#{name_condition})"
    end

    # EXISTS rather than a join: an asset that displaced the same phrase a dozen times
    # is still one result.
    def content_condition(tsquery)
      sql = "assets.content_tsv @@ #{tsquery}"
      binds = [ @query ]
      if @include_versions
        sql += " OR EXISTS (SELECT 1 FROM versions WHERE versions.asset_id = assets.id " \
               "AND versions.content_tsv @@ #{tsquery})"
        binds << @query
      end
      Asset.sanitize_sql_array([ sql, *binds ])
    end

    # The trigram index answers `<%` but not a word_similarity() call, so the operator does
    # the lookup, with the cutoff config/database.yml gives it, and the call keeps the
    # comparison strictly greater, as measured: a name scoring exactly the threshold is out.
    def name_condition
      Asset.sanitize_sql_array([ "? <% assets.name AND word_similarity(?, assets.name) > ?",
                                 @query, @query, NAME_SIMILARITY_THRESHOLD ])
    end

    def apply_sort(scope, tsquery)
      column = @sort.to_s
      return scope.reorder(column) if SORT_COLUMNS.include?(column)
      relevance_order(scope, tsquery)
    end

    # Content relevance and name similarity are not on the same scale, so adding them
    # made the weighting an accident of how ts_rank_cd happens to be distributed. Fusing
    # them by rank instead asks the only question that transfers between the two: how
    # near the top of its own list did this asset come? Measured on the eval set, this
    # lifts recall@10 from 84.2% to 89.5% and MRR from 0.797 to 0.829.
    #
    # Fusing all-terms with any-term was also tried and is markedly worse: any-term is
    # a superset of all-terms, so it contributes no independent evidence, only noise.
    def relevance_order(scope, tsquery)
      return stale_order(scope) if @query.blank?

      # A pure-name match and a pure-content match are each first in one list and second
      # in the other, so they fuse to the same score. Break that tie toward the name: if
      # you search "rails" the file called rails.md is what you meant.
      scope.joins(fusion_join(tsquery)).reorder(Arel.sql(Asset.sanitize_sql_array([
        "fusion.score DESC, word_similarity(?, assets.name) DESC, assets.id ASC", @query
      ])))
    end

    # With no query there is no relevance. The overdue list is a review queue, so it comes
    # most overdue first, as Assets::Stale orders it.
    def stale_order(scope)
      @stale ? scope.reorder(:stale_after, :dir, :name) : scope
    end

    # Each list holds only the assets its own retriever matched, under the same filters as
    # the results: an asset that misses the name threshold has no name rank, rather than
    # a place at the bottom of the name list decided by its id. rank() rather than
    # row_number(), so assets that score the same share a rank whatever their ids.
    # Grouped by id, so joining it cannot multiply rows.
    def fusion_join(tsquery)
      by_content = filters.where(content_condition(tsquery)).select(Asset.sanitize_sql_array([
        "assets.id, rank() OVER (ORDER BY ts_rank_cd(assets.content_tsv, #{tsquery}) DESC) AS rnk", @query
      ]))
      by_name = filters.where(name_condition).select(Asset.sanitize_sql_array([
        "assets.id, rank() OVER (ORDER BY word_similarity(?, assets.name) DESC) AS rnk", @query
      ]))

      <<~SQL.squish
        INNER JOIN (
          SELECT id, SUM(1.0 / (#{RRF_K} + rnk)) AS score FROM (
            #{by_content.to_sql} UNION ALL #{by_name.to_sql}
          ) ranked GROUP BY id
        ) fusion ON fusion.id = assets.id
      SQL
    end

    def apply_pagination(scope)
      scope = scope.offset(@offset.to_i) if @offset.present? && @offset.to_i.positive?
      scope = scope.limit(@limit.to_i) if @limit.present?
      scope
    end
  end
end
