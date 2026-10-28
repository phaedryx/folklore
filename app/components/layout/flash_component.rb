module Layout
  # The notice and alert a redirect or a re-render carries.
  class FlashComponent < ViewComponent::Base
    def initialize(flash:)
      @notice = flash["notice"].presence || flash[:notice].presence
      @alert = flash["alert"].presence || flash[:alert].presence
    end

    def render?
      @notice || @alert
    end
  end
end
