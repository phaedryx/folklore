require "test_helper"

class Assets::UpdateTest < ActiveSupport::TestCase
  setup do
    @actor = actor_for(:member_default, agent: "ping")
    @asset = Assets::Create.mutate(actor: @actor, path: "member/notes", name: "hello.md", content: "original")
  end

  def update(**args)
    Assets::Update.mutate(**{ actor: @actor, slug: @asset.slug }.merge(args))
  end

  test "a content change writes the new content, its sha, and a version snapshot of the old" do
    update(content: "updated", actor: actor_for(:member_default, agent: "pong"))

    @asset.reload
    assert_equal "updated", @asset.content
    assert_equal Digest::SHA256.hexdigest("updated"), @asset.content_sha256
    assert_equal 1, @asset.versions.count
    version = @asset.versions.first
    assert_equal "original", version.content
    assert_equal "text/markdown", version.content_type
    assert_equal users(:member), version.actor_user
    assert_equal tokens(:member_default), version.actor_token
    assert_equal "pong", version.actor_agent
  end

  test "stamps the updating token and agent, leaving the creator alone" do
    update(content: "updated", actor: actor_for(:member_default, agent: "pong"))

    @asset.reload
    assert_equal "ping", @asset.created_by_agent
    assert_equal "pong", @asset.updated_by_agent
    assert_equal tokens(:member_default), @asset.updated_by_token
  end

  test "bumps the version counter on a change and returns the fresh row" do
    result = update(content: "updated")

    assert_equal 1, result.lock_version
    assert_equal 1, @asset.reload.lock_version
  end

  test "an empty string clears content; nil leaves it alone" do
    update(content: nil, name: "renamed.md")
    assert_equal "original", @asset.reload.content

    update(content: "")
    assert_equal "", @asset.reload.content
    assert_equal 1, @asset.versions.count
  end

  test "unchanged content writes no version" do
    update(content: "original")

    assert_equal 0, @asset.versions.count
  end

  test "a name-only change writes no version and keeps content" do
    update(name: "renamed.md")

    assert_equal 0, @asset.versions.count
    assert_equal "renamed.md", @asset.reload.name
    assert_equal "original", @asset.content
  end

  test "content_type can change alongside content" do
    update(content: "plain", content_type: "text/plain")

    assert_equal "text/plain", @asset.reload.content_type
  end

  test "writes an asset_updated event" do
    update(content: "new")

    event = Event.where(action: "asset_updated").last
    assert_equal @asset.id, event.asset_id
    assert_equal "ping", event.actor_agent
  end

  test "tags: nil leaves tags, [] clears them, [...] replaces them with events" do
    Tags::Apply.mutate(actor: @actor, slug: @asset.slug, tag: "shell")

    update(name: "renamed.md", tags: nil)
    assert_equal %w[shell], @asset.reload.tags.pluck(:name)

    update(tags: %w[ruby onboarding])
    assert_equal %w[onboarding ruby], @asset.reload.tags.pluck(:name).sort
    assert Event.exists?(action: "tag_added", asset: @asset, metadata: { tag: "ruby" })
    assert Event.exists?(action: "tag_removed", asset: @asset, metadata: { tag: "shell" })

    update(tags: [])
    assert_empty @asset.reload.tags
  end

  test "expected_version matching the current version succeeds" do
    update(content: "v2", expected_version: 0)

    assert_equal "v2", @asset.reload.content
  end

  test "a stale expected_version raises ConflictError naming the current version and writes nothing" do
    update(content: "v2")

    error = assert_raises(Assets::ConflictError) { update(content: "v3", expected_version: 0) }

    assert_equal "#{@asset.slug} is at version 1", error.message
    assert_equal "v2", @asset.reload.content
    assert_equal 1, @asset.versions.count
  end

  test "raises NotFoundError for an unknown or deleted slug" do
    assert_raises(Assets::NotFoundError) { update(slug: "00000000", content: "x") }

    @asset.update!(deleted_at: Time.current)
    assert_raises(Assets::NotFoundError) { update(content: "x") }
  end

  test "raises ForbiddenError for another member's asset and writes nothing" do
    assert_raises(Assets::ForbiddenError) { update(actor: actor_for(:other_default), content: "v2") }

    assert_equal "original", @asset.reload.content
    assert_equal 0, @asset.versions.count
    assert_nil Event.find_by(action: "asset_updated")
  end

  test "renaming onto a live name raises NameTakenError" do
    Assets::Create.mutate(actor: @actor, path: "member/notes", name: "taken.md", content: "")

    assert_raises(Assets::NameTakenError) { update(name: "taken.md") }
    assert_equal "hello.md", @asset.reload.name
  end

  test "rejects an invalid name" do
    assert_raises(Asset::InvalidNameError) { update(name: "a b.md") }
  end
end
