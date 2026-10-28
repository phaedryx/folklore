require "test_helper"

class Users::ProvisionTest < ActiveSupport::TestCase
  test "provisions a user with a normalized email" do
    user = Users::Provision.mutate(handle: "alice", email: " A@B.com ", name: "Alice")

    assert user.persisted?
    assert_equal "a@b.com", user.email
    assert_equal "alice", user.handle
    assert_equal "Alice", user.name
    assert_nil user.password_digest
  end

  test "sets a password when given" do
    user = Users::Provision.mutate(handle: "alice", email: "a@b.com", name: "Alice", password: "hunter22")

    assert user.authenticate("hunter22")
  end

  test "defaults the name to the email's local part" do
    user = Users::Provision.mutate(handle: "alice", email: "alice@b.com", name: nil)

    assert_equal "alice", user.name
  end

  test "rejects a reserved handle" do
    error = assert_raises(ActiveRecord::RecordInvalid) do
      Users::Provision.mutate(handle: "api", email: "a@b.com", name: "A")
    end

    assert_match(/Handle is reserved/, error.message)
    refute User.exists?(email: "a@b.com")
  end

  test "rejects a malformed handle" do
    assert_raises(ActiveRecord::RecordInvalid) do
      Users::Provision.mutate(handle: "Not Valid", email: "a@b.com", name: "A")
    end
  end

  test "is idempotent on email regardless of case" do
    first = Users::Provision.mutate(handle: "alice", email: "a@b.com", name: "Alice")
    second = Users::Provision.mutate(handle: "alice2", email: "A@B.COM", name: "Other")

    assert_equal first, second
    assert_equal "alice", second.reload.handle
    assert_equal 1, User.where("lower(email) = ?", "a@b.com").count
  end
end
