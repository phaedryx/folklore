module Tags
  class Apply
    NotFoundError = Tags::NotFoundError
    ForbiddenError = Tags::ForbiddenError
    AlreadyAppliedError = Tags::AlreadyAppliedError
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
        raise AlreadyAppliedError, "tag #{@name} is already on #{@slug}" if asset.tags.exists?(name: @name)

        Tags::Change.mutate(actor: @actor, asset:, add: [ @name ])
        Tags.touch!(asset, @actor)
      end
    end
  end
end
