# Writes a bundle directory by hand, so import tests can build exactly the
# input they mean (including broken ones) without going through Export.
class BundleWriter
  attr_reader :dir

  def initialize(dir)
    @dir = dir
    @assets = []
    @versions = {}
  end

  def asset(**attrs)
    attrs = {
      slug: Asset.generate_slug, owner: "member", dir: "member/notes", content_type: "text/markdown",
      content: "body", tags: [], status: nil, stale_after: nil, verified_at: nil,
      created_at: Time.utc(2026, 1, 1, 0, 0, 0, 1), updated_at: Time.utc(2026, 1, 2, 0, 0, 0, 2)
    }.merge(attrs)
    @assets << attrs
    attrs
  end

  def versions(slug, rows)
    @versions[slug] = rows
  end

  # Writes the files and manifest. The block may change the manifest hash
  # before it is written.
  def write(manifest_counts: nil)
    entries = @assets.map do |attrs|
      file = Bundles::Format.asset_path(dir: attrs[:dir], name: attrs[:name], slug: attrs[:slug], archived: attrs[:deleted_at].present?)
      put(file, Bundles::Format.dump_asset(attrs))
      { slug: attrs[:slug], file:, sha256: Asset.sha256(attrs[:content]) }
    end
    @versions.each { |slug, rows| put(Bundles::Format.versions_path(slug), Bundles::Format.dump_versions(rows)) }

    counts = manifest_counts || {
      assets: @assets.size,
      archived: @assets.count { |a| a[:deleted_at] },
      versions: @versions.values.sum(&:size),
      tasks: @assets.count { |a| a[:task] }
    }
    manifest = { exported_at: Time.utc(2026, 10, 28), counts:, assets: entries }
    yield manifest if block_given?
    put(Bundles::Format::MANIFEST, Bundles::Format.dump_manifest(**manifest))
    self
  end

  def put(relative, content)
    path = File.join(@dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
  end
end
