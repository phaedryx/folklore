module Assets
  # The assets whose wikilinks point at the one on screen.
  class BacklinksComponent < ViewComponent::Base
    def initialize(assets:)
      @assets = assets
    end

    def render?
      @assets.any?
    end
  end
end
