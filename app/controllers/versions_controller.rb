# An asset's History page: the current content, then its versions newest
# first, PAGE_SIZE at a time. Each version renders a diff against the current
# content, so a page is kept short. Pages are numbered rather than keyed on
# an id, since an import can give an old version a new id.
class VersionsController < ApplicationController
  PAGE_SIZE = 10

  before_action -> { request.format = :html }

  def index
    @asset = Assets::Read.query(slug: params[:slug], actor: current_actor)
    @page = [ params[:page].to_i, 1 ].max
    versions = Versions::List.query(slug: @asset.slug, actor: current_actor)
                             .offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE + 1).to_a
    @more = versions.size > PAGE_SIZE
    @versions = versions.first(PAGE_SIZE)
  end

  def restore
    asset = Versions::Restore.mutate(actor: current_actor, slug: params[:slug], version_id: params[:version_id])
    redirect_to helpers.asset_url_for(asset, action: :versions), notice: "Version restored."
  end
end
