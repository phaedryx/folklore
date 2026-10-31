require "test_helper"

class DomainErrorsTest < ActiveSupport::TestCase
  test "a registered error resolves to its code, status and field" do
    entry = DomainErrors.for(Asset::InvalidNameError.new("name is required"))

    assert_equal "invalid_name", entry.code
    assert_equal :unprocessable_content, entry.status
    assert_equal :name, entry.field
  end

  test "lookup walks ancestors, so a subclass resolves to its own entry or its parent's" do
    assert_equal "reserved_path", DomainErrors.for(Asset::ReservedDirError.new("x")).code

    unregistered = Class.new(Asset::InvalidDirError)
    assert_equal "invalid_path", DomainErrors.for(unregistered.new("x")).code
  end

  test "an outcome note and a failure reason over the limit are told apart" do
    assert_equal [ "note_too_long", :note ], DomainErrors.for(Tasks::NoteTooLongError.new("x")).then { [ _1.code, _1.field ] }
    assert_equal [ "reason_too_long", :reason ], DomainErrors.for(Tasks::ReasonTooLongError.new("x")).then { [ _1.code, _1.field ] }
  end

  test "an unregistered error resolves to nil" do
    assert_nil DomainErrors.for(RuntimeError.new("boom"))
  end

  test "a code means one status wherever it is used" do
    DomainErrors::ENTRIES.values.group_by(&:code).each do |code, entries|
      assert_equal 1, entries.map(&:status).uniq.size, "#{code} has more than one status"
    end
  end

  test "every status is one the transports map" do
    DomainErrors::ENTRIES.each do |klass, entry|
      assert_includes %i[not_found forbidden conflict unprocessable_content], entry.status, klass.name
    end
  end

  test "message names what was missing or invalid, not tables and columns" do
    record = Tag.new(name: "")
    record.validate

    assert_equal "Name can't be blank", DomainErrors.message(ActiveRecord::RecordInvalid.new(record))
    assert_equal "asset", DomainErrors.message(ActiveRecord::RecordNotFound.new("Couldn't find Asset", "Asset"))
    assert_equal "record", DomainErrors.message(ActiveRecord::RecordNotFound.new("Couldn't find it"))
    assert_equal "abc12345", DomainErrors.message(Assets::NotFoundError.new("abc12345"))
  end

  test "docs/errors.md lists every code" do
    doc = Rails.root.join("docs/errors.md").read

    DomainErrors::ENTRIES.values.map(&:code).uniq.each do |code|
      assert_includes doc, "`#{code}`", "docs/errors.md does not list #{code}"
    end
  end
end
