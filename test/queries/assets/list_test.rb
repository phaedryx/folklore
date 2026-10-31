require "test_helper"

class Assets::ListTest < ActiveSupport::TestCase
  setup { @actor = actor_for(:member_default) }

  def create(name, path: "member/notes", tags: [])
    Assets::Create.mutate(actor: @actor, path:, name:, content: "", tags:)
  end

  def names(**args)
    Assets::List.query(**{ path: "member/notes", actor: @actor }.merge(args)).map(&:name)
  end

  test "returns live assets in the dir and its subtree, by name" do
    create("c.md")
    create("a.md")
    create("nested.md", path: "member/notes/sub")
    create("elsewhere.md", path: "member/scripts")
    gone = create("gone.md")
    gone.update!(deleted_at: Time.current)

    assert_equal %w[a.md c.md nested.md], names
  end

  test "tags narrow to assets carrying all of them; an unknown tag yields nothing" do
    create("both.md", tags: %w[shell onboarding])
    create("one.md", tags: %w[shell])
    create("none.md")

    assert_equal %w[both.md one.md], names(tags: %w[shell])
    assert_equal %w[both.md], names(tags: %w[shell onboarding])
    assert_empty names(tags: %w[nonexistent])
  end

  test "sort by created_at orders chronologically; unknown sorts fall back to name" do
    create("z.md").update!(created_at: 2.hours.ago)
    create("a.md").update!(created_at: 1.hour.ago)

    assert_equal %w[z.md a.md], names(sort: "created_at")
    assert_equal %w[a.md z.md], names(sort: "drop table")
  end

  test "limit and offset page the results" do
    %w[a.md b.md c.md].each { |n| create(n) }

    assert_equal %w[a.md b.md], names(limit: 2)
    assert_equal %w[b.md c.md], names(limit: 2, offset: 1)
  end

  test "a dir with no assets yields an empty relation" do
    assert_empty names(path: "member/empty")
  end

  test "a sort breaks ties by id, so pages neither skip nor repeat" do
    stamp = Time.current
    assets = %w[c.md a.md b.md].map { |name| create(name).tap { |a| a.update_columns(created_at: stamp) } }

    assert_equal assets.sort_by(&:id).map(&:name), names(sort: "created_at")
  end

  test "limit is applied as given; callers clamp it" do
    assert_equal 501, Assets::List.query(path: "member", limit: 501, actor: @actor).limit_value
  end
end
