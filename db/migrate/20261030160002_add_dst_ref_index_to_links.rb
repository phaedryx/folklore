# Links::Sync resolves inbound links by dst_ref on every create and restore;
# the unique index leads with src_asset_id, so it cannot serve that lookup.
class AddDstRefIndexToLinks < ActiveRecord::Migration[8.1]
  def change
    add_index :links, %i[dst_ref kind]
  end
end
