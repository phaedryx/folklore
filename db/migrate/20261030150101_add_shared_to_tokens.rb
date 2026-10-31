# A shared token is one several agents hold, telling themselves apart with the
# `agent` argument. Only a shared token may act as an agent other than its own.
class AddSharedToTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :tokens, :shared, :boolean, null: false, default: false
  end
end
