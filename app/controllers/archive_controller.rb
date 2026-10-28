class ArchiveController < ApplicationController
  def show
    @owner = Users::Read.query(handle: params[:handle])
    @assets = Assets::Archive.query(handle: @owner.handle, actor: current_actor)
  end

  def create
    Assets::Restore.mutate(actor: current_actor, slug: params[:slug])
    redirect_to workspace_path(handle: params[:handle])
  rescue Assets::ForbiddenError
    redirect_to workspace_archive_path(params[:handle]), alert: "You don't have permission to restore this file."
  rescue Assets::NameTakenError
    redirect_to workspace_archive_path(params[:handle]),
                alert: "Could not restore: the original location is now occupied by another file."
  end
end
