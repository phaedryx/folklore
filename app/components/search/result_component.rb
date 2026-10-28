module Search
  # One search hit: name linked to its page, its folder, its tags.
  class ResultComponent < ViewComponent::Base
    def initialize(asset:)
      @asset = asset
    end
  end
end
