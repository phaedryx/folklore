require "test_helper"
require "rake"

class FolkloreAdminTaskTest < ActiveSupport::TestCase
  ENV_KEYS = %w[FOLKLORE_ADMIN_HANDLE FOLKLORE_ADMIN_EMAIL FOLKLORE_ADMIN_PASSWORD].freeze

  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @saved = ENV_KEYS.to_h { |k| [ k, ENV.delete(k) ] }
  end

  teardown do
    @saved.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  def run_admin(**env)
    env.each { |k, v| ENV[k.to_s] = v }
    Rake::Task["folklore:admin"].reenable
    out, = capture_io { Rake::Task["folklore:admin"].invoke }
    out
  end

  test "provisions the admin and prints a token with the mcp config snippet" do
    out = run_admin(FOLKLORE_ADMIN_HANDLE: "tad", FOLKLORE_ADMIN_EMAIL: "Tad@Example.com", FOLKLORE_ADMIN_PASSWORD: "x")

    user = User.find_by!(email: "tad@example.com")
    assert_equal "tad", user.handle
    assert user.authenticate("x")
    assert_equal 1, user.tokens.count
    assert_equal "default", user.tokens.first.agent_name
    assert_match(/flk_[1-9A-HJ-NP-Za-km-z]{32}/, out)
    assert_match(/"mcpServers"/, out)
    assert_match(%r{/mcp}, out)
  end

  test "is idempotent: a second run issues no second token and prints no plaintext" do
    run_admin(FOLKLORE_ADMIN_HANDLE: "tad", FOLKLORE_ADMIN_EMAIL: "tad@example.com", FOLKLORE_ADMIN_PASSWORD: "x")
    out = run_admin(FOLKLORE_ADMIN_HANDLE: "tad", FOLKLORE_ADMIN_EMAIL: "tad@example.com", FOLKLORE_ADMIN_PASSWORD: "x")

    assert_equal 1, User.find_by!(email: "tad@example.com").tokens.count
    refute_match(/flk_[1-9A-HJ-NP-Za-km-z]{32}/, out)
    assert_match(/already/, out)
  end

  test "with no env and no terminal it explains and does nothing" do
    out = run_admin

    assert_match(/FOLKLORE_ADMIN_HANDLE/, out)
    assert_equal 2, User.count
  end
end
