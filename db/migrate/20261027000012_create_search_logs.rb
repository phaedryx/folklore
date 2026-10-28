class CreateSearchLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :search_logs do |t|
      t.text :query, null: false
      t.jsonb :filters, null: false, default: {}
      t.string :result_slugs, array: true, null: false, default: []
      t.references :token, foreign_key: true, index: false
      t.string :followed_slug
      t.datetime :created_at, null: false
    end

    add_index :search_logs, %i[token_id created_at]
  end
end
