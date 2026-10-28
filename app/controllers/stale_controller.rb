class StaleController < ApplicationController
  # The review queue for the signed-in user's own workspace.
  def index
    @assets = Assets::Stale.query(path_prefix: current_user.handle, actor: current_actor)
  end
end
