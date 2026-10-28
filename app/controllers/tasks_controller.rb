class TasksController < ApplicationController
  LIMIT = 100

  # Tasks in the signed-in user's workspace, every status unless a status
  # filter is chosen, oldest first and capped at LIMIT rows.
  def index
    @status = params[:status].presence || "all"
    @tag_names = parse_tags(params[:tags])
    tasks = Tasks::List.query(path_prefix: current_user.handle, status: @status, tags: @tag_names, actor: current_actor)
                       .limit(LIMIT + 1).to_a
    @truncated = tasks.size > LIMIT
    @tasks = tasks.first(LIMIT)
  rescue Tasks::InvalidStatusError => e
    redirect_to tasks_path, alert: e.message
  end
end
