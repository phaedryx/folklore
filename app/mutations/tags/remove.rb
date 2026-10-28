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
      ActiveRecord::Base.transaction do
        asset = Tags.writable!(@slug, @actor)
        asset_tag = asset.asset_tags.joins(:tag).find_by(tags: { name: @name })
        raise NotAppliedError, "tag #{@name} is not on #{@slug}" unless asset_tag

        asset_tag.destroy!
        Events::Record.mutate(actor: @actor, asset:, action: "tag_removed", metadata: { "tag" => @name })
        Tags.touch!(asset, @actor)
      end
    end
  end
end
