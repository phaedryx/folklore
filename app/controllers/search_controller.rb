class SearchController < ApplicationController
  LIMIT = 50

  def index
    @query = params[:q].to_s.strip
    @tag_names = parse_tags(params[:tags])
    return if @query.empty? && @tag_names.empty?

    @assets = Assets::Search.query(query: @query, tags: @tag_names, limit: LIMIT, actor: current_actor)
                            .includes(:tags).to_a
  end
end
