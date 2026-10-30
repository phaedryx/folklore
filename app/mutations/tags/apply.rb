module Tags
  class Apply
    NotFoundError = Tags::NotFoundError
    ForbiddenError = Tags::ForbiddenError
    InvalidTagError = Tags::InvalidTagError

    def self.mutate(actor:, slug:, tag:)
      new(actor:, slug:, tag:).mutate
    end

    def initialize(actor:, slug:, tag:)
      @actor = actor
      @slug = slug
      @name = Tag.normalize(tag)
    end

    def mutate
      Tag.validate_name!(@name)

      ActiveRecord::Base.transaction do
        asset = Tags.writable!(@slug, @actor)
        next Result.new(asset:, changed: false) if asset.tags.exists?(name: @name)

        Tags::Change.mutate(actor: @actor, asset:, add: [ @name ])
        Result.new(asset: Tags.touch!(asset, @actor), changed: true)
      end
    end
  end
end
