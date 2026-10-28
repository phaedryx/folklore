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
      raise InvalidTagError, "tag is required" if @name.empty?

      asset = Asset.live.find_by(slug: @slug)
      raise NotFoundError, @slug unless asset
      raise ForbiddenError, "cannot write to #{asset.location}" unless @actor.user.can_write_to_workspace?(asset.workspace_handle)
      raise AlreadyAppliedError, @name if asset.tags.exists?(name: @name)

      ActiveRecord::Base.transaction do
        AssetTag.create!(asset:, tag: Tag.find_or_create_by!(name: @name))
        Events::Record.mutate(actor: @actor, asset:, action: "tag_added", metadata: { "tag" => @name })
      end
      asset
    end
  end
end
