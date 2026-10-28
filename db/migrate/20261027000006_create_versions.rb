class CreateVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :versions do |t|
      t.references :asset, null: false, foreign_key: true, index: false
      t.text :content
      t.string :content_type
      t.references :actor_user, foreign_key: { to_table: :users }
      t.references :actor_token, foreign_key: { to_table: :tokens }
      t.string :actor_agent
      t.datetime :created_at, null: false
      t.virtual :content_tsv, type: :tsvector, as: "to_tsvector('english', coalesce(content, ''))", stored: true
    end

    add_index :versions, %i[asset_id created_at]
    add_index :versions, :content_tsv, using: :gin
  end
end
