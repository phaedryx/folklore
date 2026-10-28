module Assets
  # An asset tagged `decision`, set apart in its folder with a marker.
  class DecisionEntryComponent < ViewComponent::Base
    def initialize(asset:)
      @asset = asset
    end
  end
end
