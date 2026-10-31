require "test_helper"

class Assets::CreateTest < ActiveSupport::TestCase
  def create(**args)
    Assets::Create.mutate(**{ actor: actor_for(:member_default), path: "member/notes", name: "hello.md", content: "hi" }.merge(args))
  end

  test "creates a live asset with a slug, dir, name and content sha" do
    asset = create(path: "member/dad-jokes", name: "jokes.sh", content: "echo hello")

    assert_match(/\A[0-9a-hjkmnp-tv-z]{8}\z/, asset.slug)
    assert_equal "member/dad-jokes", asset.dir
    assert_equal "jokes.sh", asset.name
    assert_equal "member/dad-jokes/jokes.sh", asset.location
    assert_equal users(:member), asset.owner
    assert_nil asset.deleted_at
  end

  test "stamps the creating token and agent, and nothing as updater" do
    asset = create(actor: actor_for(:member_default, agent: "ping"))

    assert_equal tokens(:member_default), asset.created_by_token
    assert_equal "ping", asset.created_by_agent
    assert_nil asset.updated_by_token
    assert_nil asset.updated_by_agent
  end

  test "a web actor stamps the web agent with no token" do
    asset = create(actor: Actor.for_user(users(:member)))

    assert_nil asset.created_by_token
    assert_equal "web", asset.created_by_agent
  end

  test "writes an asset_created event in the same transaction" do
    asset = create(actor: actor_for(:member_default, agent: "ping"))

    event = Event.last
    assert_equal "asset_created", event.action
    assert_equal users(:member).id, event.actor_user_id
    assert_equal "ping", event.actor_agent
    assert_equal asset.id, event.asset_id
  end

  test "infers content_type from the name, defaulting to text/plain" do
    assert_equal "application/x-sh", create(name: "deploy.sh").content_type
    assert_equal "text/plain", create(name: "readme.blarf").content_type
    assert_equal "text/markdown", create(name: "x.md").content_type
    assert_equal "text/x-custom", create(name: "y.md", content_type: "text/x-custom").content_type
  end

  test "nil content stays nil; empty content is empty" do
    assert_nil create(name: "a.md", content: nil).content
    assert_equal "", create(name: "b.md", content: "").content
  end

  test "attaches normalized, de-duplicated tags" do
    asset = create(tags: [ "Shell", " onboarding ", "shell" ])

    assert_equal %w[onboarding shell], asset.tags.pluck(:name).sort
  end

  test "rejects a write to another member's workspace and writes nothing" do
    assert_raises(Assets::Create::ForbiddenError) { create(path: "other/notes") }

    assert_equal 0, Asset.count
    assert_equal 0, Event.count
  end

  test "rejects a path that escapes the workspace and writes nothing" do
    assert_raises(Asset::InvalidDirError) { create(path: "member/../other") }

    assert_equal 0, Asset.count
  end

  test "rejects a reserved path and writes nothing" do
    assert_raises(Asset::ReservedDirError) { create(path: "member/state") }
    assert_raises(Asset::ReservedDirError) { create(path: "member/archive") }

    assert_equal 0, Asset.count
  end

  test "reserved: true lets a checkpoint writer use the state segment" do
    asset = create(path: "member/state/ping", name: "last_session.md", reserved: true)

    assert_equal "member/state/ping", asset.dir
  end

  test "reserved: true still refuses another member's workspace" do
    assert_raises(Assets::Create::ForbiddenError) { create(path: "other/state/ping", reserved: true) }
  end

  test "rejects a duplicate name at the same dir, from the database constraint" do
    create

    assert_raises(Assets::Create::NameTakenError) { create(content: "v2") }
    assert_equal 1, Asset.count
  end

  test "a tombstoned asset does not take the name" do
    first = create
    first.update!(deleted_at: Time.current)

    assert_equal "hello.md", create.name
  end

  test "rejects invalid names" do
    assert_raises(Asset::InvalidNameError) { create(name: "has space.md") }
    assert_raises(Asset::InvalidNameError) { create(name: "sub/dir.md") }
    assert_raises(Asset::InvalidNameError) { create(name: "..") }
  end

  test "rejects invalid dirs" do
    assert_raises(Asset::InvalidDirError) { create(path: "/member/notes") }
    assert_raises(Asset::InvalidDirError) { create(path: "member/notes/") }
    assert_raises(Asset::InvalidDirError) { create(path: "member//notes") }
    assert_raises(Asset::InvalidDirError) { create(path: "member/tasks/rebase-on-main.md") }
  end

  test "accepts a dotted segment that is not a known extension" do
    assert_equal "member/tools.v1", create(path: "member/tools.v1").dir
  end

  test "refuses content over the cap with a domain error and writes nothing" do
    assert_raises(Asset::ContentTooLargeError) { create(content: "x" * (Asset::MAX_CONTENT_BYTES + 1)) }
    assert_equal 0, Asset.count

    assert_nothing_raised { create(content: "x" * Asset::MAX_CONTENT_BYTES) }
  end
end
