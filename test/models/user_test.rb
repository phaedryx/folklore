require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "requires email" do
    user = User.new(name: "Alice")
    refute user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "email is unique (case-insensitive)" do
    User.create!(email: "alice@example.com", name: "Alice")
    dup = User.new(email: "ALICE@EXAMPLE.COM", name: "Alice2")
    refute dup.valid?
    assert_includes dup.errors[:email], "has already been taken"
  end

  test "no callback normalizes email; it is stored as given" do
    user = User.create!(email: "A@B.com", name: "Alice")
    assert_equal "A@B.com", user.reload.email
  end

  test "email format is enforced" do
    user = User.new(email: "not-an-email", name: "Alice")
    refute user.valid?
    assert_includes user.errors[:email], "is invalid"
  end

  test "email is immutable" do
    user = User.create!(email: "alice@example.com", name: "Alice")
    user.email = "alice2@example.com"
    refute user.valid?
    assert_includes user.errors[:email], "is immutable"
  end

  test "requires name" do
    user = User.new(email: "alice@example.com")
    refute user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test "handle is optional on create" do
    user = User.create!(email: "alice@example.com", name: "Alice")
    assert_nil user.handle
  end

  test "valid handles are accepted" do
    valid = %w[alice alice2 t-2 ab a1 longhandle-here-with-numbers12]
    valid.each_with_index do |h, i|
      user = User.new(email: "u#{i}@example.com", name: "U", handle: h)
      assert user.valid?, "expected #{h.inspect} to be valid (got: #{user.errors.full_messages})"
    end
  end

  test "invalid handles are rejected" do
    bad = {
      "T" => "uppercase",
      "1tad" => "starts with digit",
      "-alice" => "starts with dash",
      "alice-" => "ends with dash",
      "alice--x" => "doubled dash",
      "Alice" => "uppercase letter",
      "tad_x" => "underscore not allowed",
      "a" => "too short (1 char)",
      "a" * 33 => "too long (33 chars)"
    }
    bad.each do |h, reason|
      user = User.new(email: "u@example.com", name: "U", handle: h)
      refute user.valid?, "expected #{h.inspect} (#{reason}) to be invalid"
    end
  end

  test "reserved handles are rejected" do
    assert_equal %w[mcp api auth assets rails settings sign_in sign_out files search tasks stale activity verifications up], User::RESERVED_HANDLES
    User::RESERVED_HANDLES.each do |h|
      user = User.new(email: "u#{h}@example.com", name: "U", handle: h)
      refute user.valid?, "expected #{h.inspect} to be rejected as reserved"
      assert_includes user.errors[:handle], "is reserved"
    end
  end

  test "handle is unique" do
    User.create!(email: "alice@example.com", name: "Alice", handle: "alice")
    dup = User.new(email: "bob@example.com", name: "Bob", handle: "alice")
    refute dup.valid?
    assert_includes dup.errors[:handle], "has already been taken"
  end

  test "handle is immutable once set" do
    user = User.create!(email: "alice@example.com", name: "Alice", handle: "alice")
    user.handle = "alice2"
    refute user.valid?
    assert_includes user.errors[:handle], "is immutable once set"
  end

  test "handle can be set on existing user with nil handle" do
    user = User.create!(email: "alice@example.com", name: "Alice")
    user.handle = "alice"
    assert user.save
    assert_equal "alice", user.reload.handle
  end

  test "a user writes only to their own workspace" do
    assert users(:member).can_write_to_workspace?("member")
    refute users(:member).can_write_to_workspace?("other")
  end

  test "authenticate_by_email finds the user case-insensitively and checks the password" do
    assert_equal users(:member), User.authenticate_by_email(" Member@Example.com ", "member-secret")
    assert_nil User.authenticate_by_email("member@example.com", "wrong")
    assert_nil User.authenticate_by_email("ghost@example.com", "member-secret")
    assert_nil User.authenticate_by_email("other@example.com", "")
  end

  test "password is optional but authenticates when set" do
    user = User.create!(email: "alice@example.com", name: "Alice")
    assert_nil user.password_digest

    user.update!(password: "hunter22")
    assert user.authenticate("hunter22")
    refute user.authenticate("wrong")
  end
end
