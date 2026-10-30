module Assets
  # Gives a live asset a new directory, and a new name when one is passed. The
  # slug stays, so links to it keep resolving. Writes stay inside the owner's
  # workspace: the destination must be one the actor may write to.
  class Move
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    NameTakenError = Assets::NameTakenError

    def self.mutate(actor:, slug:, path:, name: nil)
      new(actor:, slug:, path:, name:).mutate
    end

    def initialize(actor:, slug:, path:, name:)
      @actor = actor
      @slug = slug
      @path = path.to_s
      @name = name
    end

    def mutate
      Asset.validate_dir!(@path)
      Asset.validate_name!(@name) unless @name.nil?
      raise ForbiddenError, "cannot write to #{@path}" unless @actor.user.can_write_to_workspace?(@path.split("/").first)

      ActiveRecord::Base.transaction(requires_new: true) do
        asset = Assets.writable!(@slug, @actor)
        # A checkpoint is found by its place under <handle>/state; moved, it is lost.
        Asset.validate_dir!(asset.dir)
        from = asset.location
        asset.dir = @path
        asset.name = @name unless @name.nil?
        @to = asset.location
        # A move to where it already is changes nothing and records nothing.
        next asset unless asset.changed?

        asset.updated_by_token = @actor.token
        asset.updated_by_agent = @actor.agent
        asset.save!
        Events::Record.mutate(actor: @actor, asset:, action: "asset_moved", metadata: { "from" => from, "to" => @to })
        asset
      end
    rescue ActiveRecord::RecordNotUnique
      raise NameTakenError, "#{@to} already exists"
    end
  end
end
