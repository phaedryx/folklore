module Versions
  # A live asset's prior contents, newest first. An archived asset keeps its
  # history, but like the asset itself it is not found until restored.
  class List
    def self.query(slug:, actor: nil)
      asset = Assets::Read.query(slug:, actor:)
      asset.versions.includes(:actor_user).order(created_at: :desc, id: :desc)
    end
  end
end
