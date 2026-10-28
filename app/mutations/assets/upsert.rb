module Assets
  # Create-or-update by location: updates the live asset at dir + name when
  # there is one, otherwise creates it.
  class Upsert
    Result = Data.define(:asset, :created)

    def self.mutate(actor:, path:, name:, content: nil, content_type: nil, tags: nil, reserved: false)
      new(actor:, path:, name:, content:, content_type:, tags:, reserved:).mutate
    end

    def initialize(actor:, path:, name:, content:, content_type:, tags:, reserved:)
      @actor = actor
      @path = path.to_s
      @name = name.to_s
      @content = content
      @content_type = content_type
      @tags = tags
      @reserved = reserved
    end

    def mutate
      existing = Asset.live.find_by(dir: @path, name: @name)
      return update(existing) if existing

      create
    rescue Assets::NameTakenError
      # Lost the race to another writer creating the same location: update
      # what they created, which is what an upsert promises.
      update(Asset.live.find_by!(dir: @path, name: @name))
    end

    private

    def update(asset)
      updated = Assets::Update.mutate(actor: @actor, slug: asset.slug, content: @content, content_type: @content_type, tags: @tags)
      Result.new(asset: updated, created: false)
    end

    def create
      asset = Assets::Create.mutate(actor: @actor, path: @path, name: @name, content: @content,
                                    content_type: @content_type, tags: @tags || [], reserved: @reserved)
      Result.new(asset:, created: true)
    end
  end
end
