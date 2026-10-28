# Agents sharing one token are told apart everywhere else (events, versions,
# task claims); the search log recorded only the token, so one agent's read
# could mark another's search as followed.
class AddActorAgentToSearchLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :search_logs, :actor_agent, :string
    add_index :search_logs, [ :token_id, :actor_agent, :created_at ]
  end
end
