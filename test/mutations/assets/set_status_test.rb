require "test_helper"

class Assets::SetStatusTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default)
    @note = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "n.md", content: "")
  end

  def set(status, **args)
    Assets::SetStatus.mutate(**{ actor: @actor, slug: @note.slug, status: }.merge(args))
  end

  test "sets open and done, and clears on nil or empty string" do
    assert_equal "open", set("open").status
    assert_equal "done", set("done").status
    assert_nil set(nil).status
    set("open")
    assert_nil set("").status
  end

  test "writes an asset_status_set event carrying the status" do
    set("done")

    event = Event.where(asset_id: @note.id).last
    assert_equal "asset_status_set", event.action
    assert_equal({ "status" => "done" }, event.metadata)
  end

  test "rejects a task asset" do
    Task.create!(asset: @note, status: "pending")

    assert_raises(Assets::NotANoteError) { set("done") }
  end

  test "rejects an unknown status" do
    assert_raises(Assets::InvalidStatusError) { set("in_progress") }
  end

  test "raises NotFoundError for unknown or deleted, ForbiddenError for another member" do
    assert_raises(Assets::NotFoundError) { set("done", slug: "00000000") }
    assert_raises(Assets::ForbiddenError) { set("done", actor: actor_for(:other_default)) }

    @note.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { set("done") }
  end
end
