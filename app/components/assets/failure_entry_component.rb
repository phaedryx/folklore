module Assets
  # An asset tagged `failure`, set apart in its folder with a marker.
  class FailureEntryComponent < ViewComponent::Base
    def initialize(asset:)
      @asset = asset
    end
  end
end
