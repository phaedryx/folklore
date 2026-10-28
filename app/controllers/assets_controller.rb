class AssetsController < ApplicationController
  # Asset names end in extensions (.md, .json) that would otherwise be read
  # as the response format.
  before_action -> { request.format = :html }

  def show
    @asset = Assets::Read.query(slug: params[:slug], actor: current_actor)
    return redirect_to helpers.asset_url_for(@asset), status: :moved_permanently unless canonical_address?

    if ActiveModel::Type::Boolean.new.cast(params[:raw])
      # Stored content is untrusted: a sandboxed response gets an opaque
      # origin, so HTML or SVG served raw cannot script this one.
      response.headers["Content-Security-Policy"] = "sandbox"
      return render plain: @asset.content.to_s, content_type: @asset.content_type.presence || "text/plain"
    end

    @backlinks = Links::Backlinks.query(asset: @asset)
  end

  def new
    @path = params[:path].to_s
    @name = params[:name].to_s
  end

  def create
    @asset = Assets::Create.mutate(
      actor: current_actor,
      path: asset_params[:path].to_s,
      name: asset_params[:name].to_s,
      content: normalize_newlines(asset_params[:content]),
      tags: parse_tags(asset_params[:tags])
    )
    redirect_to helpers.asset_url_for(@asset)
  rescue Assets::ForbiddenError => e
    render_new(e.message, :forbidden)
  rescue Assets::NameTakenError, Asset::InvalidNameError, Asset::InvalidDirError, Asset::ContentTooLargeError => e
    render_new(e.message, :unprocessable_content)
  end

  def edit
    @asset = Assets::Read.query(slug: params[:slug], actor: current_actor)
    raise Assets::ForbiddenError, @asset.location unless current_user.can_write_to_workspace?(@asset.workspace_handle)

    fill_form_from(@asset)
  end

  def update
    @asset = Assets::Update.mutate(
      actor: current_actor,
      slug: params[:slug],
      content: normalize_newlines(asset_params[:content]),
      name: asset_params[:name],
      tags: parse_tags(asset_params[:tags]),
      expected_version: asset_params[:expected_version]
    )
    redirect_to helpers.asset_url_for(@asset), notice: "Saved."
  rescue Assets::ConflictError
    @asset = Assets::Read.query(slug: params[:slug], actor: current_actor)
    fill_form_from(@asset)
    @draft = normalize_newlines(asset_params[:content])
    flash.now[:alert] = "This file changed since you opened it. Nothing was saved: the form now holds the " \
                        "current version, and your text is below to copy back in."
    render :edit, status: :conflict
  rescue Assets::NameTakenError, Asset::InvalidNameError, Asset::ContentTooLargeError => e
    @asset = Assets::Read.query(slug: params[:slug], actor: current_actor)
    @error = e.message
    @name = asset_params[:name]
    @tags = asset_params[:tags]
    @content = normalize_newlines(asset_params[:content])
    @expected_version = asset_params[:expected_version]
    render :edit, status: :unprocessable_content
  end

  def destroy
    asset = Assets::Delete.mutate(actor: current_actor, slug: params[:slug])
    redirect_to helpers.asset_folder_path(asset), notice: "Archived #{asset.name}."
  rescue Assets::ForbiddenError
    redirect_back fallback_location: root_path, alert: "You don't have permission to archive this file."
  end

  private

  def asset_params
    params.require(:asset).permit(:path, :name, :content, :tags, :expected_version)
  end

  def canonical_address?
    params[:name] == @asset.name && [ params[:handle], params[:location] ].compact.join("/") == @asset.dir
  end

  def fill_form_from(asset)
    @name = asset.name
    @tags = asset.tags.map(&:name).sort.join(", ")
    @content = asset.content
    @expected_version = asset.lock_version
  end

  def render_new(error, status)
    @error = error
    @path = asset_params[:path].to_s
    @name = asset_params[:name].to_s
    @content = normalize_newlines(asset_params[:content])
    @tags = asset_params[:tags]
    render :new, status:
  end
end
