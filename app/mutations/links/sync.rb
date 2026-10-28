module Links
  # Placeholder until the wikilink parser lands: content writes call this so
  # the call sites are in place, and it does nothing yet.
  class Sync
    def self.mutate(asset:)
      asset
    end
  end
end
