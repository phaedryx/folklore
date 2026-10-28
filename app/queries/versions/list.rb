module Versions
  # An asset's prior contents, newest first. Tombstoned assets keep their
  # history, so the lookup does not require a live asset.
  class List
    def self.query(slug:, actor: nil)
      asset = Asset.find_by(slug:) or raise Assets::NotFoundError, slug
      asset.versions.includes(:actor_user).order(created_at: :desc, id: :desc)
    end
  end
end
