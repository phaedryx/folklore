module Layout
  # The path under a workspace as links, one per directory segment.
  class BreadcrumbComponent < ViewComponent::Base
    def initialize(handle:, location: nil)
      @handle = handle
      @location = location
    end

    def render?
      @location.present?
    end

    def crumbs
      segments = @location.split("/")
      segments.each_with_index.map do |label, i|
        { label:, url: helpers.workspace_path(handle: @handle, location: segments[0..i].join("/")) }
      end
    end
  end
end
