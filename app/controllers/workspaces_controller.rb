class WorkspacesController < ApplicationController
  def show
    @owner = Users::Read.query(handle: params[:handle])
    @location = params[:location].presence
    @dir = [ @owner.handle, @location ].compact.join("/")
    @listing = Assets::Browse.query(dir: @dir, actor: current_actor)
    @own_workspace = current_user.can_write_to_workspace?(@owner.handle)
    @show_archive_card = @own_workspace && @location.nil? &&
                         Assets::Archive.query(handle: @owner.handle, actor: current_actor).exists?
  end
end
