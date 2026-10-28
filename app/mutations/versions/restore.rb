module Versions
  # Append-only restore: the current head is snapshotted, then content is set
  # to the chosen version's. The chosen version is never consumed.
  class Restore
    NotFoundError = Versions::NotFoundError

    def self.mutate(actor:, slug:, version_id:)
      new(actor:, slug:, version_id:).mutate
    end

    def initialize(actor:, slug:, version_id:)
      @actor = actor
      @slug = slug
      @version_id = version_id
    end

    def mutate
      ActiveRecord::Base.transaction do
        asset = Assets.writable!(@slug, @actor)
        version = asset.versions.find_by(id: @version_id)
        raise NotFoundError, "version #{@version_id} is not on #{@slug}" unless version

        # Restoring the text the asset already has changes nothing and records nothing.
        return asset if version.content == asset.content && version.content_type == asset.content_type

        if version.content != asset.content
          Version.create!(asset:, content: asset.content, content_type: asset.content_type,
                          actor_user: @actor.user, actor_token: @actor.token, actor_agent: @actor.agent)
          asset.update!(content: version.content, content_type: version.content_type,
                        content_sha256: Asset.sha256(version.content),
                        updated_by_token: @actor.token, updated_by_agent: @actor.agent)
          Links::Sync.mutate(asset:)
        end

        Events::Record.mutate(actor: @actor, asset:, action: "version_restored",
                              metadata: { "restored_from_version_id" => version.id })
        asset
      end
    end
  end
end
