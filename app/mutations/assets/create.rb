module Assets
  # Creates a live asset under the actor's own workspace. Uniqueness of
  # (dir, name) among live assets is the database's call: the partial unique
  # index decides the race, and its violation surfaces as NameTakenError.
  class Create
    ForbiddenError = Assets::ForbiddenError
    NameTakenError = Assets::NameTakenError

    def self.mutate(actor:, path:, name:, content: nil, content_type: nil, tags: [], reserved: false)
      new(actor:, path:, name:, content:, content_type:, tags:, reserved:).mutate
    end

    def initialize(actor:, path:, name:, content:, content_type:, tags:, reserved:)
      @actor = actor
      @path = path.to_s
      @name = name.to_s
      @content = content
      @content_type = content_type
      @tags = Array(tags)
      @reserved = reserved
    end

    def mutate
      Asset.validate_dir!(@path, allow_reserved: @reserved)
      Asset.validate_name!(@name)
      Asset.validate_content!(@content)
      unless @actor.user.can_write_to_workspace?(@path.split("/").first)
        raise ForbiddenError, "cannot write to #{@path}"
      end

      asset = nil
      # A savepoint, so a unique violation inside a caller's transaction
      # (an upsert retry, a task add) does not abort the caller.
      ActiveRecord::Base.transaction(requires_new: true) do
        asset = Asset.create!(
          owner: @actor.user,
          slug: Asset.generate_slug,
          dir: @path,
          name: @name,
          content: @content,
          content_type: resolve_content_type,
          content_sha256: Asset.sha256(@content),
          created_by_token: @actor.token,
          created_by_agent: @actor.agent
        )
        Tag.attach(asset, @tags)
        Links::Sync.mutate(asset:)
        Events::Record.mutate(actor: @actor, asset:, action: "asset_created")
      end
      asset
    rescue ActiveRecord::RecordNotUnique
      raise NameTakenError, "#{@path}/#{@name} already exists"
    end

    private

    def resolve_content_type
      return @content_type if @content_type.present?

      Asset.infer_content_type(@name)
    end
  end
end
