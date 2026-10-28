require "test_helper"

class VersionsTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  def versions_path_for(asset) = "/#{asset.dir}/#{asset.slug}/#{asset.name}/versions"

  test "lists the current content and each prior version with who wrote it and a diff against current" do
    asset = create_asset(name: "h.md", content: "v1")
    Assets::Update.mutate(actor: actor_for(:member_default, agent: "ping"), slug: asset.slug, content: "v2")
    version = asset.versions.sole

    get versions_path_for(asset)
    assert_response :success
    assert_select "[data-testid='version-head']", text: /v2/
    assert_select "[data-testid='version-#{version.id}'] [data-testid='version-actor']", text: "member/ping"
    assert_select "[data-testid='version-diff-#{version.id}'] [data-diff-side='old'] .diff-removed", text: "v1"
  end

  test "an asset with no history says so" do
    asset = create_asset(name: "h.md", content: "v1")

    get versions_path_for(asset)
    assert_select "[data-testid='versions-empty']"
  end

  test "restoring a version brings its content back and keeps the head as a new version" do
    asset = create_asset(name: "h.md", content: "v1")
    Assets::Update.mutate(actor: web_actor, slug: asset.slug, content: "v2")
    version = asset.versions.sole

    post "#{versions_path_for(asset)}/#{version.id}/restore"

    assert_redirected_to versions_path_for(asset)
    assert_equal "v1", asset.reload.content
    assert_equal 2, asset.versions.count
  end

  test "another member sees no restore button and cannot restore" do
    theirs = create_asset(path: "other/notes", name: "t.md", content: "v1", fixture: :other)
    Assets::Update.mutate(actor: web_actor(:other), slug: theirs.slug, content: "v2")
    version = theirs.versions.sole

    get versions_path_for(theirs)
    assert_select "[data-testid='restore-version-#{version.id}']", false

    post "#{versions_path_for(theirs)}/#{version.id}/restore"
    assert_response :forbidden
    assert_equal "v2", theirs.reload.content
  end

  test "a version id from another asset is a 404" do
    a = create_asset(name: "a.md", content: "1")
    b = create_asset(name: "b.md", content: "1")
    Assets::Update.mutate(actor: web_actor, slug: b.slug, content: "2")

    post "#{versions_path_for(a)}/#{b.versions.sole.id}/restore"
    assert_response :not_found
  end

  test "the show page links to the history" do
    asset = create_asset(name: "h.md")

    get "/#{asset.dir}/#{asset.slug}/#{asset.name}"
    assert_select "[data-testid='asset-history'][href=?]", versions_path_for(asset)
  end
end
