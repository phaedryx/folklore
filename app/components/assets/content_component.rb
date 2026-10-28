module Assets
  # An asset's body as the show page displays it: markdown, highlighted code
  # or plain text, as Markdown::Renderer decides.
  class ContentComponent < ViewComponent::Base
    def initialize(asset:)
      @asset = asset
    end

    def render?
      @asset.content.present?
    end

    def before_render
      @rendered = Markdown::Renderer.call(
        @asset.content,
        content_type: @asset.content_type,
        name: @asset.name,
        asset_url: ->(target) { helpers.asset_url_for(target) }
      )
    end
  end
end
