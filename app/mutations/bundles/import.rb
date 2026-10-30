module Bundles
  # Reads a bundle directory (see docs/bundle.md) into this instance.
  #
  # Every problem in the bundle is collected before anything is written, and
  # any problem refuses the whole bundle. The write is one transaction:
  # assets keep their slugs and timestamps, their tags, versions and task
  # rows follow, wikilinks are synced once every asset is in (so a link to an
  # asset later in the bundle resolves; archived assets get theirs when
  # restored, as they would here), and each asset gets one
  # asset_imported event. A dry run does all of that and rolls it back.
  class Import
    class RejectedError < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super("bundle refused: #{errors.size} problem#{'s' unless errors.size == 1}")
      end
    end

    Report = Data.define(:counts, :dangling_links, :dry_run)

    # The agent named on every asset_imported event.
    AGENT = "import".freeze
    BATCH_SIZE = 500
    SLUG_REGEX = /\A[0-9a-z]{1,64}\z/
    IMPORTABLE_TASK_STATUSES = (Task::STATUSES - %w[in_progress]).freeze

    def self.mutate(dir:, dry_run: false)
      new(dir:, dry_run:).mutate
    end

    def initialize(dir:, dry_run:)
      @dir = dir.to_s
      @dry_run = dry_run
      @errors = []
    end

    def mutate
      assets, versions = read
      check_instance(assets)
      raise RejectedError, @errors if @errors.any?

      report = nil
      # A savepoint, so a dry run inside a caller's transaction rolls back
      # only what it wrote.
      ActiveRecord::Base.transaction(requires_new: true) do
        report = write(assets, versions)
        raise ActiveRecord::Rollback if @dry_run
      end
      report
    end

    private

    # -- reading and checking ------------------------------------------------

    def read
      manifest = read_manifest
      return [ [], {} ] unless manifest

      assets = read_assets(manifest[:assets])
      versions = read_versions(assets.to_h { |a| [ a[:slug], a ] })
      check_unlisted(manifest[:assets])
      # A file that failed to load is already reported; counting around it
      # would only add a second error for the same problem.
      check_counts(manifest[:counts], assets, versions) if @errors.empty?
      [ assets, versions ]
    end

    def read_manifest
      path = File.join(@dir, Format::MANIFEST)
      return reject("#{Format::MANIFEST} does not exist in #{@dir}") unless File.file?(path)

      Format.load_manifest(File.read(path))
    rescue Format::InvalidError => e
      reject(e.message)
    end

    def read_assets(entries)
      seen = {}
      entries.filter_map do |entry|
        file = entry[:file].to_s
        if seen[entry[:slug]]
          reject("#{file}: slug #{entry[:slug].inspect} is listed twice in the manifest")
          next
        end
        seen[entry[:slug]] = true
        read_asset(entry, file)
      end
    end

    def read_asset(entry, file)
      return reject("#{file.inspect} is not a path under assets/ or archived/") unless bundle_path?(file)

      path = File.join(@dir, file)
      return reject("#{file} does not exist") unless File.file?(path)

      asset = Format.load_asset(File.binread(path), file:)
      problems = asset_problems(asset, entry, file)
      return reject(*problems) if problems.any?

      asset.merge(file:)
    rescue Format::InvalidError => e
      reject(e.message)
    end

    def asset_problems(asset, entry, file)
      slug = asset[:slug]
      return [ "#{file}: slug #{slug.inspect} is not a valid slug" ] unless slug.is_a?(String) && slug.match?(SLUG_REGEX)
      return [ "#{file}: slug #{slug} does not match the manifest's #{entry[:slug].inspect}" ] unless slug == entry[:slug]

      problems = []
      problems << "#{file} (#{slug}): sha256 does not match the manifest" unless Asset.sha256(asset[:content]) == entry[:sha256]
      problems.concat(location_problems(asset, file))
      problems.concat(field_problems(asset, file))
      problems
    end

    def location_problems(asset, file)
      dir, name = asset[:dir].to_s, asset[:name].to_s
      Asset.validate_dir!(dir, allow_reserved: state_dir?(dir))
      Asset.validate_name!(name)
      expected = Format.asset_path(dir:, name:, slug: asset[:slug], archived: asset[:deleted_at].present?)
      problems = []
      problems << "#{file} (#{asset[:slug]}): should be at #{expected}" unless expected == file
      if asset[:owner] != dir.split("/").first
        problems << "#{file}: owner #{asset[:owner].inspect} does not own the workspace #{dir.split('/').first.inspect}"
      end
      problems
    rescue Asset::InvalidDirError, Asset::InvalidNameError => e
      [ "#{file}: #{e.message}" ]
    end

    # The reserved state segment holds checkpoints, which live exactly at
    # <handle>/state/<agent> or <handle>/state/<token>/<agent> (see
    # Checkpoint.dir_for); nothing else may be imported under it.
    def state_dir?(dir)
      segments = dir.split("/")
      segments.size.between?(3, 4) && segments[1] == Checkpoint::SEGMENT &&
        segments.drop(2).all? { |segment| segment.match?(Actor::AGENT_REGEX) }
    end

    def field_problems(asset, file)
      problems = []
      begin
        Asset.validate_content!(asset[:content])
      rescue Asset::ContentTooLargeError => e
        problems << "#{file}: #{e.message}"
      end
      problems << "#{file}: created_at and updated_at are required" unless asset[:created_at] && asset[:updated_at]
      problems.concat(tag_problems(asset, file))
      problems.concat(asset[:task] ? task_problems(asset, file) : status_problems(asset, file))
      problems
    end

    def tag_problems(asset, file)
      Array(asset[:tags]).map { |n| Tag.normalize(n) }.reject(&:empty?).filter_map do |name|
        Tag.validate_name!(name)
        nil
      rescue Tag::InvalidNameError => e
        "#{file}: #{e.message}"
      end
    end

    def status_problems(asset, file)
      return [] if asset[:status].nil? || Asset::NOTE_STATUSES.include?(asset[:status])

      [ "#{file}: status must be null, open or done, got #{asset[:status].inspect}" ]
    end

    def task_problems(asset, file)
      task = asset[:task]
      problems = []
      problems << "#{file}: a task's top-level status must be null, got #{asset[:status].inspect}" unless asset[:status].nil?
      if task[:status] == "in_progress"
        problems << "#{file}: task status in_progress cannot be imported; write it as pending"
      elsif !IMPORTABLE_TASK_STATUSES.include?(task[:status])
        problems << "#{file}: task status must be one of #{IMPORTABLE_TASK_STATUSES.join(', ')}, got #{task[:status].inspect}"
      end
      problems << "#{file}: task created_at and updated_at are required" unless task[:created_at] && task[:updated_at]
      begin
        Tasks.validate_note!(task[:outcome_note], "task outcome_note")
      rescue Tasks::InvalidNoteError => e
        problems << "#{file}: #{e.message}"
      end
      problems
    end

    def read_versions(assets_by_slug)
      Dir.glob("*", base: File.join(@dir, Format::VERSIONS_DIR)).sort.each_with_object({}) do |entry, versions|
        file = File.join(Format::VERSIONS_DIR, entry)
        slug = entry.delete_suffix(".jsonl")
        next reject("#{file} is not a <slug>.jsonl file") unless entry.end_with?(".jsonl")
        next reject("#{file} names no asset in the bundle") unless assets_by_slug.key?(slug)

        versions[slug] = Format.load_versions(File.read(File.join(@dir, file)), file:)
      rescue Format::InvalidError => e
        reject(e.message)
      end
    end

    def check_unlisted(entries)
      listed = entries.to_set { |e| e[:file] }
      Dir.glob("{#{Format::ASSETS_DIR},#{Format::ARCHIVED_DIR}}/**/*", File::FNM_DOTMATCH, base: @dir).sort.each do |file|
        next if File.directory?(File.join(@dir, file)) || listed.include?(file)

        reject("#{file} is not listed in the manifest")
      end
    end

    def check_counts(counts, assets, versions)
      counts(assets, versions).each do |key, value|
        next if counts[key] == value

        reject("manifest counts.#{key} is #{counts[key].inspect} but the bundle has #{value}")
      end
    end

    # Checks the bundle against what is already here: owners must exist,
    # slugs must be new, and no live location may be taken twice.
    def check_instance(assets)
      users = User.where(handle: assets.pluck(:owner).uniq).pluck(:handle)
      assets.each do |asset|
        reject("#{asset[:file]}: owner #{asset[:owner].inspect} is not a user here") unless users.include?(asset[:owner])
      end

      Asset.where(slug: assets.pluck(:slug)).pluck(:slug).each { |slug| reject("#{slug} already exists on this instance") }

      live = assets.reject { |a| a[:deleted_at] }
      live.group_by { |a| [ a[:dir], a[:name] ] }.each do |(dir, name), group|
        reject("#{dir}/#{name} is the location of #{group.size} live assets in the bundle") if group.size > 1
      end
      here = Asset.live.where(dir: live.pluck(:dir).uniq).pluck(:dir, :name).to_set
      live.each do |a|
        reject("#{a[:dir]}/#{a[:name]} is taken by a live asset here") if here.include?([ a[:dir], a[:name] ])
      end
    end

    def bundle_path?(file)
      segments = file.split("/")
      [ Format::ASSETS_DIR, Format::ARCHIVED_DIR ].include?(segments.first) && segments.size > 1 &&
        segments.none? { |s| s.empty? || s == "." || s == ".." }
    end

    def reject(*messages)
      @errors.concat(messages)
      nil
    end

    # -- writing ------------------------------------------------------------

    def write(assets, versions)
      now = Time.current
      users = User.where(handle: assets.pluck(:owner) + version_handles(versions)).index_by(&:handle)
      ids = insert_assets(assets, users)
      insert_tags(assets, ids, now)
      insert_versions(versions, ids, users)
      insert_tasks(assets, ids)

      imported = Asset.where(id: ids.values).preload(:owner)
      imported.live.find_each { |asset| Links::Sync.mutate(asset:) }
      imported.find_each do |asset|
        Events::Record.mutate(actor: Actor.new(user: asset.owner, token: nil, agent: AGENT), asset:, action: "asset_imported")
      end

      Report.new(counts: counts(assets, versions), dangling_links: dangling_links(ids.values), dry_run: @dry_run)
    end

    def insert_assets(assets, users)
      rows = assets.map do |a|
        {
          owner_id: users.fetch(a[:owner]).id, slug: a[:slug], dir: a[:dir], name: a[:name],
          content: a[:content], content_type: a[:content_type], content_sha256: Asset.sha256(a[:content]),
          lock_version: 0, status: a[:status], stale_after: a[:stale_after], verified_at: a[:verified_at],
          deleted_at: a[:deleted_at], created_at: a[:created_at], updated_at: a[:updated_at]
        }
      end
      rows.each_slice(BATCH_SIZE).each_with_object({}) do |batch, ids|
        Asset.insert_all!(batch, returning: %w[id slug], record_timestamps: false).each { |row| ids[row["slug"]] = row["id"] }
      end
    end

    def insert_tags(assets, ids, now)
      names_by_slug = assets.to_h { |a| [ a[:slug], a[:tags].map { |n| Tag.normalize(n) }.reject(&:empty?).uniq ] }
      names = names_by_slug.values.flatten.uniq
      return if names.empty?

      Tag.insert_all(names.map { |name| { name:, created_at: now, updated_at: now } }, unique_by: :name, record_timestamps: false)
      tag_ids = Tag.where(name: names).pluck(:name, :id).to_h
      rows = names_by_slug.flat_map do |slug, tag_names|
        tag_names.map { |name| { asset_id: ids.fetch(slug), tag_id: tag_ids.fetch(name), created_at: now, updated_at: now } }
      end
      rows.each_slice(BATCH_SIZE) { |batch| AssetTag.insert_all!(batch, record_timestamps: false) }
    end

    def insert_versions(versions, ids, users)
      rows = versions.flat_map do |slug, list|
        list.map do |v|
          user, agent = actor_for(v[:actor], users)
          {
            asset_id: ids.fetch(slug), content: v[:content], content_type: v[:content_type],
            actor_user_id: user&.id, actor_agent: agent, created_at: v[:created_at]
          }
        end
      end
      rows.each_slice(BATCH_SIZE) { |batch| Version.insert_all!(batch, record_timestamps: false) }
    end

    def insert_tasks(assets, ids)
      rows = assets.select { |a| a[:task] }.map do |a|
        task = a[:task]
        {
          asset_id: ids.fetch(a[:slug]), status: task[:status], attempts: task[:attempts], outcome_note: task[:outcome_note],
          created_at: task[:created_at], updated_at: task[:updated_at]
        }
      end
      rows.each_slice(BATCH_SIZE) { |batch| Task.insert_all!(batch, record_timestamps: false) }
    end

    def version_handles(versions)
      versions.values.flatten.filter_map { |v| v[:actor]&.split("/", 2)&.first }.uniq
    end

    # "handle" or "handle/agent". A handle that is not a user here leaves
    # the version without an actor.
    def actor_for(label, users)
      return [ nil, nil ] if label.blank?

      handle, agent = label.split("/", 2)
      user = users[handle]
      user ? [ user, agent.presence ] : [ nil, nil ]
    end

    def counts(assets, versions)
      {
        assets: assets.size,
        archived: assets.count { |a| a[:deleted_at] },
        versions: versions.values.sum(&:size),
        tasks: assets.count { |a| a[:task] }
      }
    end

    def dangling_links(asset_ids)
      Link.where(src_asset_id: asset_ids, dst_asset_id: nil).joins(:src_asset)
          .order("assets.dir", "assets.name", :dst_ref)
          .pluck("assets.slug", "assets.dir", "assets.name", :dst_ref)
          .map { |slug, dir, name, ref| { slug:, location: "#{dir}/#{name}", ref: } }
    end
  end
end
