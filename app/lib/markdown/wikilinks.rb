module Markdown
  # The `[[slug]]` / `[[slug|label]]` syntax. One regex, shared by the
  # renderer and the link sync so both agree on what counts as a link.
  module Wikilinks
    PATTERN = /\[\[(#{Asset::SLUG_PATTERN})(?:\|([^\]\n|]+))?\]\]/

    # Unique referenced slugs, in order of first appearance.
    def self.refs(text)
      text.to_s.scan(PATTERN).map(&:first).uniq
    end
  end
end
