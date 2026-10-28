module Tags
  class Remove
    NotFoundError = Tags::NotFoundError
    ForbiddenError = Tags::ForbiddenError
    NotAppliedError = Tags::NotAppliedError

    def self.mutate(actor:, slug:, tag:)
      new(actor:, slug:, tag:).mutate
    end

    def initialize(actor:, slug:, tag:)
      @actor = actor
      @slug = slug
      @name = Tag.normalize(tag)
    end

    def mutate
      asset = Asset.live.find_by(slug: @slug)
      raise NotFoundError, @slug unless asset
      raise ForbiddenError, "cannot write to #{asset.location}" unless @actor.user.can_write_to_workspace?(asset.workspace_handle)

      asset_tag = asset.asset_tags.joins(:tag).find_by(tags: { name: @name })
      raise NotAppliedError, "tag #{@name} is not on #{@slug}" unless asset_tag

      ActiveRecord::Base.transaction do
        asset_tag.destroy!
        Events::Record.mutate(actor: @actor, asset:, action: "tag_removed", metadata: { "tag" => @name })
      end
      asset
    end
  end
end
