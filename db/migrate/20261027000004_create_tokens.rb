class CreateTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agent_name, null: false
      t.string :token_digest, null: false
      t.string :scopes, array: true, null: false, default: %w[read write]
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :tokens, :token_digest, unique: true
    add_index :tokens, %i[user_id agent_name]
  end
end
