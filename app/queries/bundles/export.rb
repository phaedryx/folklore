require "fileutils"

module Bundles
  # Writes every asset, live and archived, to a bundle directory (see
  # docs/bundle.md). Reads only; the bundle is a snapshot taken in one
  # repeatable-read transaction, so the manifest agrees with the files.
  class Export
    NotEmptyError = Class.new(StandardError)
    Result = Data.define(:counts)

    BATCH_SIZE = 500

    def self.query(dir:, handle: nil)
      new(dir:, handle:).query
    end

    def initialize(dir:, handle:)
      @dir = dir.to_s
      @handle = handle.presence
    end

    def query
      raise NotEmptyError, "#{@dir} is not empty" if Dir.exist?(@dir) && !Dir.empty?(@dir)

      FileUtils.mkdir_p(@dir)
      counts = { assets: 0, archived: 0, versions: 0, tasks: 0 }
      entries = []

      Asset.transaction(isolation: :repeatable_read) do
        scope.find_each(batch_size: BATCH_SIZE) do |asset|
          entries << write_asset(asset)
          counts[:assets] += 1
          counts[:archived] += 1 if asset.deleted_at?
          counts[:tasks] += 1 if asset.task
          counts[:versions] += write_versions(asset)
        end
      end

      write(Format::MANIFEST, Format.dump_manifest(exported_at: Time.current, counts:, assets: entries))
      Result.new(counts:)
    end

    private

    def scope
      scope = Asset.preload(:owner, :tags, :task, versions: :actor_user)
      @handle ? scope.under_dir(@handle) : scope
    end

    def write_asset(asset)
      file = Format.asset_path(dir: asset.dir, name: asset.name, slug: asset.slug, archived: asset.deleted_at?)
      write(file, Format.dump_asset(attributes(asset)))
      { slug: asset.slug, file:, sha256: Asset.sha256(asset.content) }
    end

    def attributes(asset)
      {
        slug: asset.slug,
        owner: asset.owner.handle,
        dir: asset.dir,
        name: asset.name,
        content_type: asset.content_type,
        content: asset.content,
        tags: asset.tags.map(&:name).sort,
        status: asset.status,
        stale_after: asset.stale_after,
        verified_at: asset.verified_at,
        created_at: asset.created_at,
        updated_at: asset.updated_at,
        deleted_at: asset.deleted_at,
        task: asset.task && task_attributes(asset.task)
      }
    end

    # A claim belongs to an agent running against this instance, so an
    # in-progress task leaves as pending, ready to be claimed again.
    def task_attributes(task)
      {
        status: task.status == "in_progress" ? "pending" : task.status,
        attempts: task.attempts,
        outcome_note: task.outcome_note,
        created_at: task.created_at,
        updated_at: task.updated_at
      }
    end

    def write_versions(asset)
      versions = asset.versions.sort_by { |v| [ v.created_at, v.id ] }
      return 0 if versions.empty?

      rows = versions.map do |version|
        { content: version.content, content_type: version.content_type, created_at: version.created_at, actor: actor(version) }
      end
      write(Format.versions_path(asset.slug), Format.dump_versions(rows))
      rows.size
    end

    def actor(version)
      handle = version.actor_user&.handle
      return nil unless handle

      version.actor_agent.present? ? Actor.label(handle, version.actor_agent) : handle
    end

    def write(relative, content)
      path = File.join(@dir, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite(path, content)
    end
  end
end
