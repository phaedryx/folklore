class CreateLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :links do |t|
      t.references :src_asset, null: false, foreign_key: { to_table: :assets }, index: false
      t.references :dst_asset, foreign_key: { to_table: :assets }, index: false
      t.string :dst_ref, null: false
      t.string :kind, null: false
      t.datetime :created_at, null: false

      t.check_constraint "kind IN ('wikilink')", name: "links_kind_check"
    end

    add_index :links, %i[src_asset_id dst_ref kind], unique: true
    add_index :links, %i[dst_asset_id kind]
  end
end
