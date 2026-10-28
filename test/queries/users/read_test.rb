require "test_helper"

class Users::ReadTest < ActiveSupport::TestCase
  test "finds a user by handle" do
    assert_equal users(:other), Users::Read.query(handle: "other")
  end

  test "an unknown handle is not found" do
    assert_raises(ActiveRecord::RecordNotFound) { Users::Read.query(handle: "ghost") }
  end
end
