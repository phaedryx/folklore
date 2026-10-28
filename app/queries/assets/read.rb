module Assets
  # One live asset by slug. Every member reads every workspace, so the actor
  # is accepted for the day read scoping arrives and not consulted yet.
  class Read
    NotFoundError = Assets::NotFoundError

    def self.query(slug:, actor: nil)
      Asset.live.find_by(slug:) or raise NotFoundError, slug
    end
  end
end
