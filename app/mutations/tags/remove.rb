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
        raise NotAppliedError, "tag #{@name} is not on #{@slug}" unless asset.tags.exists?(name: @name)

        Tags::Change.mutate(actor: @actor, asset:, remove: [ @name ])
        Tags.touch!(asset, @actor)
      end
    end
  end
end
