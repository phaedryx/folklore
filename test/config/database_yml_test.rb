require "test_helper"

class DatabaseYmlTest < ActiveSupport::TestCase
  def configured_test_database(suffix)
    original = ENV["FOLKLORE_DB_SUFFIX"]
    suffix.nil? ? ENV.delete("FOLKLORE_DB_SUFFIX") : ENV["FOLKLORE_DB_SUFFIX"] = suffix
    yaml = ERB.new(Rails.root.join("config/database.yml").read).result
    YAML.safe_load(yaml, aliases: true).dig("test", "database")
  ensure
    ENV["FOLKLORE_DB_SUFFIX"] = original
  end

  test "FOLKLORE_DB_SUFFIX is appended to the test database name" do
    assert_equal "folklore_test_x", configured_test_database("x")
  end

  test "the test database name is unsuffixed when FOLKLORE_DB_SUFFIX is unset" do
    assert_equal "folklore_test", configured_test_database(nil)
  end
end
