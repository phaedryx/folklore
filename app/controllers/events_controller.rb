# The activity page: newest first, a page at a time. `before_id` pages back
# and `since_id` catches up on what happened after an event, both by id so
# no event is skipped at a page boundary.
class EventsController < ApplicationController
  PAGE_SIZE = 50

  def index
    @actor_filter = params[:actor].presence
    @tag_filter = params[:tag].presence
    @since_id = Events::List.parse_cursor(:since_id, params[:since_id].presence)
    events = Events::List.query(actor: @actor_filter, tag: @tag_filter, since_id: @since_id,
                                before_id: params[:before_id].presence, limit: PAGE_SIZE).to_a
    # since_id reads forward, oldest first; the page shows newest first either way.
    @events = @since_id ? events.reverse : events
    @full_page = events.size == PAGE_SIZE
  end

  private

  # A bad cursor drops the cursor and keeps the filters.
  def error_fallback_location
    activity_path(actor: @actor_filter, tag: @tag_filter)
  end
end
