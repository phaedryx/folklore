module Layout
  # The page chrome: brand, primary nav for a signed-in user, and the main
  # column the page renders into.
  class ShellComponent < ViewComponent::Base
    def initialize(current_user: nil, wide: false)
      @current_user = current_user
      @wide = wide
    end

    def signed_in?
      @current_user&.handle.present?
    end

    def main_class
      if @wide
        "w-full flex-1 min-h-0"
      else
        "mx-auto w-full max-w-6xl flex-1 px-6 py-8"
      end
    end

    NAV_LINK = "inline-flex items-center gap-1.5 text-primary hover:text-primary-hover no-underline".freeze
  end
end
