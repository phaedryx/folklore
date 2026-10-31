# Nothing read assets.content_sha256: bundle export and import hash the
# content they write or check, so the column only had to be kept in step by
# every writer.
class RemoveContentSha256FromAssets < ActiveRecord::Migration[8.1]
  def change
    remove_column :assets, :content_sha256, :string
  end
end
