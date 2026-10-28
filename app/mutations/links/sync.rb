module Links
  # Keeps the links table in step with one asset, in both directions:
  #
  # - a live asset's outbound wikilink rows are made to match its content,
  #   each resolved to the live asset with that slug or left dangling
  #   (dst_asset_id nil, dst_ref kept) when there is none;
  # - inbound rows naming this asset's slug are resolved to it when it is
  #   live and unresolved when it is tombstoned, so dst_asset_id is set
  #   exactly when the target is live.
  #
  # Called inside the transaction of every mutation that writes content or
  # flips deleted_at.
  class Sync
    KIND = "wikilink".freeze

    def self.mutate(asset:)
      new(asset).mutate
    end

    def initialize(asset)
      @asset = asset
    end

    def mutate
      if @asset.deleted_at?
        unresolve_inbound
      else
        sync_outbound
        resolve_inbound
      end
      @asset
    end

    private

    def sync_outbound
      wanted = Markdown::Wikilinks.refs(@asset.content)
      existing = @asset.links.where(kind: KIND).index_by(&:dst_ref)

      (existing.keys - wanted).each { |ref| existing[ref].destroy! }

      targets = Asset.live.where(slug: wanted).pluck(:slug, :id).to_h
      wanted.each do |ref|
        link = existing[ref] || @asset.links.build(dst_ref: ref, kind: KIND)
        link.dst_asset_id = targets[ref]
        link.save! if link.new_record? || link.changed?
      end
    end

    def resolve_inbound
      Link.where(dst_ref: @asset.slug, kind: KIND, dst_asset_id: nil).update_all(dst_asset_id: @asset.id)
    end

    def unresolve_inbound
      Link.where(dst_asset_id: @asset.id, kind: KIND).update_all(dst_asset_id: nil)
    end
  end
end
