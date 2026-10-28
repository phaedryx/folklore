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

  TTY_STDIN = Class.new(StringIO) { def tty? = true }

  # Swaps $stdin so the task never waits on the real terminal, whether or not
  # the test runner has one.
  def run_admin(tty: false, **env)
    env.each { |k, v| ENV[k.to_s] = v }
    original = $stdin
    $stdin = tty ? TTY_STDIN.new : StringIO.new
    Rake::Task["folklore:admin"].reenable
    out, = capture_io { Rake::Task["folklore:admin"].invoke }
    out
  ensure
    $stdin = original
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

  test "with a terminal but CI set it does not prompt" do
    ENV["CI"] = "1"
    out = run_admin(tty: true)

    assert_match(/FOLKLORE_ADMIN_HANDLE/, out)
    assert_equal 2, User.count
  ensure
    ENV.delete("CI")
  end

  test "a second run adds a password to an admin provisioned without one" do
    run_admin(FOLKLORE_ADMIN_HANDLE: "tad", FOLKLORE_ADMIN_EMAIL: "tad@example.com")
    run_admin(FOLKLORE_ADMIN_HANDLE: "tad", FOLKLORE_ADMIN_EMAIL: "tad@example.com", FOLKLORE_ADMIN_PASSWORD: "later")

    assert User.find_by!(email: "tad@example.com").authenticate("later")
  end

  test "with no env and no terminal it explains and does nothing" do
    out = run_admin

    assert_match(/FOLKLORE_ADMIN_HANDLE/, out)
    assert_equal 2, User.count
  end
end
