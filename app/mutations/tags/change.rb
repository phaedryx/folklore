module Tags
  # The one place an asset's tag set changes: attaches and detaches the named
  # (already normalized) tags and records a tag event for each. It leaves the
  # asset row alone, since Tags::Apply and Tags::Remove touch it as an edit of
  # their own while Assets::Update folds the change into its save.
  class Change
    def self.mutate(actor:, asset:, add: [], remove: [])
      add.each do |name|
        AssetTag.create!(asset:, tag: Tag.find_or_insert!(name))
        Events::Record.mutate(actor:, asset:, action: "tag_added", metadata: { "tag" => name })
      end

      remove.each do |name|
        asset.asset_tags.joins(:tag).find_by!(tags: { name: }).destroy!
        Events::Record.mutate(actor:, asset:, action: "tag_removed", metadata: { "tag" => name })
      end
      asset
    end
  end
end
