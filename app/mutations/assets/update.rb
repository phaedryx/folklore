module Assets
  # Edits a live asset under a row lock, so two writers serialise and each
  # snapshots exactly what it overwrote. `expected_version` lets a caller
  # refuse to overwrite an edit it has not seen.
  class Update
    NotFoundError = Assets::NotFoundError
    ForbiddenError = Assets::ForbiddenError
    ConflictError = Assets::ConflictError
    NameTakenError = Assets::NameTakenError

    def self.mutate(actor:, slug:, content: nil, name: nil, content_type: nil, tags: nil, expected_version: nil)
      new(actor:, slug:, content:, name:, content_type:, tags:, expected_version:).mutate
    end

    def initialize(actor:, slug:, content:, name:, content_type:, tags:, expected_version:)
      @actor = actor
      @slug = slug
      @content = content
      @name = name
      @content_type = content_type
      @tags = tags
      @expected_version = expected_version
    end

    def mutate
      Asset.validate_name!(@name) if @name.present?
      Asset.validate_content!(@content)

      ActiveRecord::Base.transaction(requires_new: true) do
        asset = Assets.writable!(@slug, @actor)
        check_version!(asset)

        content_changed = !@content.nil? && @content != asset.content
        snapshot(asset) if content_changed
        if content_changed
          asset.content = @content
          asset.content_sha256 = Asset.sha256(@content)
        end
        asset.content_type = @content_type if @content_type.present?
        asset.name = @name if @name.present?
        tags_changed = @tags.nil? ? false : sync_tags(asset)
        # A call that changes nothing writes nothing: no stamp, no version
        # bump, no event.
        return asset unless asset.changed? || tags_changed

        asset.updated_by_token = @actor.token
        asset.updated_by_agent = @actor.agent
        # Tags live in their own table; touching the row makes a tags-only
        # change bump lock_version like any other edit.
        asset.updated_at = Time.current
        asset.save!

        Links::Sync.mutate(asset:) if content_changed
        Events::Record.mutate(actor: @actor, asset:, action: "asset_updated")
        asset
      end
    rescue ActiveRecord::RecordNotUnique
      raise NameTakenError, "#{@name} already exists in that directory"
    end

    private

    def check_version!(asset)
      return if @expected_version.blank? || @expected_version.to_i == asset.lock_version

      raise ConflictError, "#{asset.slug} is at version #{asset.lock_version}"
    end

    def snapshot(asset)
      Version.create!(
        asset:,
        content: asset.content,
        content_type: asset.content_type,
        actor_user: @actor.user,
        actor_token: @actor.token,
        actor_agent: @actor.agent
      )
    end

    # Returns whether the set changed.
    def sync_tags(asset)
      wanted = @tags.map { |t| Tag.normalize(t) }.reject(&:empty?).uniq
      wanted.each { |name| Tag.validate_name!(name) }
      current = asset.tags.pluck(:name)

      (wanted - current).each do |name|
        AssetTag.create!(asset:, tag: Tag.find_or_insert!(name))
        Events::Record.mutate(actor: @actor, asset:, action: "tag_added", metadata: { "tag" => name })
      end

      (current - wanted).each do |name|
        asset.asset_tags.joins(:tag).find_by!(tags: { name: }).destroy!
        Events::Record.mutate(actor: @actor, asset:, action: "tag_removed", metadata: { "tag" => name })
      end

      wanted.sort != current.sort
    end
  end
end
