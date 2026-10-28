module Assets
  # A workspace's tombstoned assets, most recently deleted first.
  class Archive
    def self.query(handle:, actor: nil)
      Asset.tombstoned.under_dir(handle.to_s).includes(:owner).order(deleted_at: :desc)
    end
  end
end
