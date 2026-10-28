module Assets
  # One asset as a row: name linked to its page, content type, tag chips.
  class CardComponent < ViewComponent::Base
    def initialize(asset:)
      @asset = asset
    end
  end
end
