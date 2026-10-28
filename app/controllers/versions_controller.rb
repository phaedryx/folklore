class VersionsController < ApplicationController
  before_action -> { request.format = :html }

  def index
    @asset = Assets::Read.query(slug: params[:slug], actor: current_actor)
    @versions = Versions::List.query(slug: @asset.slug, actor: current_actor)
  end

  def restore
    asset = Versions::Restore.mutate(actor: current_actor, slug: params[:slug], version_id: params[:version_id])
    redirect_to helpers.asset_url_for(asset, action: :versions), notice: "Version restored."
  end
end
