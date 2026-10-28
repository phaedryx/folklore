class CreateAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :assets do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :slug, null: false
      t.text :dir, null: false
      t.string :name, null: false
      t.text :content
      t.string :content_type
      t.string :content_sha256
      t.integer :lock_version, null: false, default: 0
      t.string :status
      t.date :stale_after
      t.datetime :verified_at
      t.references :verified_by_token, foreign_key: { to_table: :tokens }
      t.datetime :deleted_at
      t.references :created_by_token, foreign_key: { to_table: :tokens }
      t.references :updated_by_token, foreign_key: { to_table: :tokens }
      t.timestamps
      t.virtual :content_tsv, type: :tsvector, as: "to_tsvector('english', coalesce(content, ''))", stored: true

      t.check_constraint "status IS NULL OR status IN ('open', 'done')", name: "assets_status_check"
      t.check_constraint "octet_length(content) <= 1048576", name: "assets_content_size_check"
    end

    add_index :assets, :slug, unique: true
    add_index :assets, %i[dir name], unique: true, where: "deleted_at IS NULL", name: "index_assets_on_dir_and_name_live"
    add_index :assets, :dir, opclass: :text_pattern_ops
    add_index :assets, :content_tsv, using: :gin
    add_index :assets, :name, using: :gin, opclass: :gin_trgm_ops
    add_index :assets, :stale_after
  end
end
