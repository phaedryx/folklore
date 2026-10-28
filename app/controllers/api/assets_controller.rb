module Api
  class AssetsController < BaseController
    def index
      assets = ::Assets::List.query(path: params.require(:path), tags: Array(params[:tags]), actor: current_actor)
      render_success({ assets: assets.map { |asset| AssetSerializer.call(asset) } })
    end

    def show
      asset = ::Assets::Read.query(slug: params[:slug], actor: current_actor)
      render_success({ asset: AssetSerializer.call(asset) })
    end

    def create
      attrs = params.require(:asset).permit(:path, :name, :content, :content_type, tags: [])
      asset = ::Assets::Create.mutate(
        actor: current_actor,
        path: attrs[:path],
        name: attrs[:name],
        content: attrs[:content],
        content_type: attrs[:content_type],
        tags: attrs[:tags] || []
      )
      render_success({ asset: AssetSerializer.call(asset) }, status: :created)
    end

    def update
      attrs = params.require(:asset).permit(:content, :name, :content_type, :expected_version, tags: [])
      asset = ::Assets::Update.mutate(
        actor: current_actor,
        slug: params[:slug],
        content: attrs[:content],
        name: attrs[:name],
        content_type: attrs[:content_type],
        tags: attrs.key?(:tags) ? attrs[:tags] : nil,
        expected_version: attrs[:expected_version]
      )
      render_success({ asset: AssetSerializer.call(asset) })
    end

    def destroy
      ::Assets::Delete.mutate(actor: current_actor, slug: params[:slug])
      render_success({ archived: true })
    end
  end
end
