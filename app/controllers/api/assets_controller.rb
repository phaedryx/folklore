module Api
  class AssetsController < BaseController
    # A page of the index, unless the request asks for another size; a size
    # outside 1..MAX_LIMIT is clamped to it rather than refused.
    DEFAULT_LIMIT = 100
    MAX_LIMIT = 500

    # `next_offset` is where the next page starts, or nil on the last one.
    def index
      limit = (params[:limit].presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      offset = [ params[:offset].to_i, 0 ].max
      assets = ::Assets::List.query(path: params.require(:path), tags: Array(params[:tags]), limit: limit + 1, offset:,
                                    actor: current_actor)
                             .preload(Assets::Serializer::PRELOADS).to_a
      next_offset = offset + limit if assets.size > limit
      render_success({ assets: assets.first(limit).map { |asset| Assets::Serializer.call(asset) }, next_offset: })
    end

    def show
      asset = ::Assets::Read.query(slug: params[:slug], actor: current_actor)
      render_success({ asset: Assets::Serializer.call(asset) })
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
      render_success({ asset: Assets::Serializer.call(asset) }, status: :created)
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
      render_success({ asset: Assets::Serializer.call(asset) })
    end

    def destroy
      ::Assets::Delete.mutate(actor: current_actor, slug: params[:slug])
      render_success({ archived: true })
    end
  end
end
