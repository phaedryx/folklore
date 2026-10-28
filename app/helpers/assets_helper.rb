module AssetsHelper
  # The page for an asset, addressed by its current dir and name. The slug
  # is what the route resolves; the rest keeps the URL readable.
  def asset_url_for(asset, action: :show)
    handle, location = asset.dir.split("/", 2)
    args = { handle:, location:, slug: asset.slug, name: asset.name }

    case action
    when :show then leaf_path(**args)
    when :raw then leaf_path(**args, raw: true)
    when :edit then edit_leaf_path(**args)
    when :versions then leaf_versions_path(**args)
    else raise ArgumentError, "no asset page for #{action.inspect}"
    end
  end

  def asset_version_restore_path(asset, version)
    handle, location = asset.dir.split("/", 2)
    leaf_version_restore_path(handle:, location:, slug: asset.slug, name: asset.name, version_id: version.id)
  end

  def writable?(asset)
    current_user&.can_write_to_workspace?(asset.workspace_handle)
  end

  # The browse URL for the folder an asset sits in.
  def asset_folder_path(asset)
    handle, location = asset.dir.split("/", 2)
    workspace_path(handle:, location:)
  end
end
