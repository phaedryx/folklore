class TasksController < ApplicationController
  # Every task in the signed-in user's workspace, all statuses unless a
  # status filter is chosen.
  def index
    @status = params[:status].presence || "all"
    @tag_names = parse_tags(params[:tags])
    @tasks = Tasks::List.query(path_prefix: current_user.handle, status: @status, tags: @tag_names, actor: current_actor)
                        .includes(task: :claimed_by_user).to_a
  rescue Tasks::InvalidStatusError => e
    redirect_to tasks_path, alert: e.message
  end
end
