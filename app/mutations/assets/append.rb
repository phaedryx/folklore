module Assets
  # Adds text to the end of an asset, on its own line. An Update underneath,
  # so the prior content is snapshotted.
  class Append
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError

    def self.mutate(actor:, slug:, text:)
      new(actor:, slug:, text:).mutate
    end

    def initialize(actor:, slug:, text:)
      @actor = actor
      @slug = slug
      @text = text.to_s
    end

    def mutate
      ActiveRecord::Base.transaction do
        asset = Assets.writable!(@slug, @actor)
        asset.lock!
        Assets::Update.mutate(actor: @actor, slug: @slug, content: combined(asset.content.to_s))
      end
    end

    private

    def combined(existing)
      separator = existing.empty? || existing.end_with?("\n") ? "" : "\n"
      "#{existing}#{separator}#{@text}"
    end
  end
end
