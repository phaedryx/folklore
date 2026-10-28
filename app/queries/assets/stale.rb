module Assets
  # The review queue: live assets whose stale_after has passed, most overdue
  # first. Assets that never set a review date are not stale.
  class Stale
    def self.query(path_prefix: nil, actor: nil)
      scope = Asset.live.stale.includes(:tags, :owner, :verified_by_token).order(:stale_after, :dir, :name)
      scope = scope.under_dir(path_prefix.to_s) if path_prefix.present?
      scope
    end
  end
end
