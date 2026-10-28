# Search eval: where does each expected asset land for each query?
#
#   FOLKLORE_EVAL_QUERIES=script/search_eval_queries.yml bin/rails runner script/search_eval.rb
#   bin/rails "folklore:search_eval[script/search_eval_queries.yml]"
#
# The queries file names real assets, so script/search_eval_queries*.yml is gitignored.
# Metrics live in SearchEval::Scorecard; the loop in SearchEval::Runner. Both are tested.
SearchEval::Runner.call(ENV["FOLKLORE_EVAL_QUERIES"])
