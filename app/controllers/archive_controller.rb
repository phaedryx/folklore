class ArchiveController < ApplicationController
  def show
    @owner = Users::Read.query(handle: params[:handle])
    @assets = Assets::Archive.query(handle: @owner.handle, actor: current_actor)
  end

  def create
    Assets::Restore.mutate(actor: current_actor, slug: params[:slug])
    redirect_to workspace_path(handle: params[:handle])
  end

  private

  def error_fallback_location
    workspace_archive_path(params[:handle])
  end
end
