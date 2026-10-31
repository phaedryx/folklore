# Search eval: where does each expected asset land for each query?
#
#   FOLKLORE_EVAL_QUERIES=script/search_eval_queries.yml bin/rails runner script/search_eval.rb
#   bin/rails "folklore:search_eval[script/search_eval_queries.yml]"
#
# The queries file names real assets, so script/search_eval_queries*.yml is gitignored.
# Without one, this runs the committed synthetic set in script/search_eval/.
# Metrics live in SearchEval::Scorecard; the loop in SearchEval::Runner. Both are tested.
if ENV["FOLKLORE_EVAL_QUERIES"].present?
  SearchEval::Runner.call(ENV["FOLKLORE_EVAL_QUERIES"])
else
  SearchEval::Synthetic.call
end
