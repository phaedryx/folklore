module Layout
  # The workspace page header: the owner's handle and the breadcrumb below it.
  class HeaderComponent < ViewComponent::Base
    def initialize(owner:, location: nil)
      @owner = owner
      @location = location
    end
  end
end
