require "test_helper"

class SchemaTest < ActiveSupport::TestCase
  def connection
    ActiveRecord::Base.connection
  end

  test "assets have a partial unique index on dir and name for live rows" do
    index = connection.indexes(:assets).find { |i| i.columns == %w[dir name] }

    assert index, "expected an index on assets(dir, name)"
    assert index.unique
    assert_match(/deleted_at IS NULL/i, index.where)
  end

  test "content_tsv is a stored generated column on assets and versions" do
    %w[assets versions].each do |table|
      row = connection.select_one(<<~SQL)
        SELECT is_generated, generation_expression
        FROM information_schema.columns
        WHERE table_name = '#{table}' AND column_name = 'content_tsv'
      SQL

      assert row, "#{table}.content_tsv is missing"
      assert_equal "ALWAYS", row["is_generated"]
      assert_match(/to_tsvector\('english'/, row["generation_expression"])
    end
  end

  test "no database triggers exist" do
    count = connection.select_value("SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal")

    assert_equal 0, count
  end

  test "assets record the acting agent for create, update and verify" do
    %w[created_by_agent updated_by_agent verified_by_agent].each do |column|
      assert connection.column_exists?(:assets, column), "assets.#{column} is missing"
    end
  end

  test "every phase 1 table exists" do
    %w[users tokens assets versions tags asset_tags tasks links events search_logs].each do |table|
      assert connection.table_exists?(table), "missing table #{table}"
    end
  end

  test "the events action check matches Event::ACTIONS" do
    definition = connection.select_value(<<~SQL)
      SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'events_action_check'
    SQL

    assert_equal Event::ACTIONS.sort, definition.scan(/'([a-z_]+)'/).flatten.sort
  end

  test "pg_trgm is enabled" do
    assert connection.extension_enabled?("pg_trgm")
  end
end

class ModelCallbackTest < ActiveSupport::TestCase
  test "no model declares a lifecycle callback" do
    offenders = Dir[Rails.root.join("app/models/**/*.rb")].select do |file|
      File.read(file).match?(/^\s*(before|after|around)_[a-z_]+\b|dependent:/)
    end

    assert_empty offenders.map { |f| f.delete_prefix(Rails.root.to_s) }
  end
end
