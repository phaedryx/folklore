require "test_helper"

class TagTest < ActiveSupport::TestCase
  test "validate_name! rejects a blank name and one over the length limit, naming it" do
    assert_nothing_raised { Tag.validate_name!("t" * Tag::MAX_NAME_LENGTH) }
    assert_equal "tag is required", assert_raises(Tag::InvalidNameError) { Tag.validate_name!("") }.message
    error = assert_raises(Tag::InvalidNameError) { Tag.validate_name!("t" * (Tag::MAX_NAME_LENGTH + 1)) }
    assert_equal "tag is 101 characters, over the 100 character limit", error.message
  end

  test "a name over the limit is rejected by the database" do
    assert_raises(ActiveRecord::StatementInvalid) { Tag.insert({ name: "t" * (Tag::MAX_NAME_LENGTH + 1) }) }
  end

  test "find_or_insert! returns the existing row or inserts one" do
    existing = Tag.create!(name: "old")

    assert_equal existing, Tag.find_or_insert!("old")
    assert_difference -> { Tag.count }, 1 do
      assert_equal "new", Tag.find_or_insert!("new").name
    end
  end
end
