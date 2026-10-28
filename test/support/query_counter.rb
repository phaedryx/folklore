# Counts the SQL statements a block runs, ignoring schema and transaction
# chatter, so a test can pin that a serialized list does not grow a query per row.
module QueryCounter
  IGNORED = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i

  def count_queries(matching: nil)
    queries = []
    callback = lambda do |*, payload|
      next if payload[:name] == "SCHEMA" || payload[:sql].match?(IGNORED)

      queries << payload[:sql] if matching.nil? || payload[:sql].match?(matching)
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries.size
  end
end

ActiveSupport::TestCase.include(QueryCounter)
