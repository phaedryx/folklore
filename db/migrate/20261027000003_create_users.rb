class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :handle
      t.string :email, null: false
      t.string :name
      t.string :password_digest
      t.timestamps
    end

    add_index :users, :handle, unique: true
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
  end
end
