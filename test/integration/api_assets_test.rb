require "test_helper"

class ApiAssetsTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  def headers(plaintext = "flk_test_member")
    JSON_HEADERS.merge("Authorization" => "Bearer #{plaintext}")
  end

  def body
    JSON.parse(response.body)
  end

  def create(name, content: "", path: "member/notes", **attrs)
    ::Assets::Create.mutate(actor: actor_for(:member_default), path:, name:, content:, **attrs)
  end

  # Auth

  test "401 without a bearer token, with an unknown one, and with a revoked one" do
    get "/api/assets", params: { path: "member/notes" }, headers: JSON_HEADERS
    assert_equal 401, response.status
    assert_equal "Bearer", response.headers["WWW-Authenticate"]
    assert_equal "unauthenticated", body.dig("data", "resource")

    get "/api/assets", params: { path: "member/notes" }, headers: headers("flk_nope")
    assert_equal 401, response.status

    get "/api/assets", params: { path: "member/notes" }, headers: headers("flk_test_member_revoked")
    assert_equal 401, response.status
  end

  # Index

  test "index requires path and returns the serialized assets under it" do
    get "/api/assets", headers: headers
    assert_equal 422, response.status
    assert_includes body.dig("data", "path"), "is required"

    create("a.md", content: "hello", tags: [ "x" ])
    create("b.md", path: "member/scripts")

    get "/api/assets", params: { path: "member/notes" }, headers: headers
    assert_equal 200, response.status
    assets = body.dig("data", "assets")
    assert_equal 1, assets.size
    assert_equal "a.md", assets.first["name"]
    assert_equal "hello", assets.first["content"]
    assert_equal "member/notes/a.md", assets.first["location"]
    assert_equal [ "x" ], assets.first["tags"]
    assert_equal({ "handle" => "member", "agent" => "default" }, assets.first["created_by"])

    get "/api/assets", params: { path: "member/notes", tags: [ "nope" ] }, headers: headers
    assert_equal [], body.dig("data", "assets")
  end

  # Show

  test "show returns one asset by slug, 404 for unknown or archived" do
    asset = create("show.md", content: "hi")

    get "/api/assets/#{asset.slug}", headers: headers("flk_test_other")
    assert_equal 200, response.status
    assert_equal "hi", body.dig("data", "asset", "content")

    get "/api/assets/00000000", headers: headers
    assert_equal 404, response.status
    assert_equal "asset_not_found", body.dig("data", "resource")
  end

  # Create

  test "create returns 201 with the asset, stamped with the token's agent" do
    post "/api/assets", params: { asset: { path: "member/notes", name: "new.md", content: "body", tags: %w[a b] } }.to_json, headers: headers
    assert_equal 201, response.status
    assert_equal "new.md", body.dig("data", "asset", "name")
    assert_equal %w[a b], body.dig("data", "asset", "tags").sort
    assert_equal({ "handle" => "member", "agent" => "default" }, body.dig("data", "asset", "created_by"))
  end

  test "create maps forbidden, taken, reserved and invalid to 403 and 422" do
    create("dup.md")

    post "/api/assets", params: { asset: { path: "other/notes", name: "x.md" } }.to_json, headers: headers
    assert_equal 403, response.status

    post "/api/assets", params: { asset: { path: "member/notes", name: "dup.md" } }.to_json, headers: headers
    assert_equal 422, response.status
    assert_includes body.dig("data", "name"), "already taken at this path"

    post "/api/assets", params: { asset: { path: "member/archive", name: "x.md" } }.to_json, headers: headers
    assert_equal 422, response.status
    assert_match(/reserved/, body.dig("data", "path").first)

    post "/api/assets", params: { asset: { path: "member/notes", name: "a b.md" } }.to_json, headers: headers
    assert_equal 422, response.status
    assert_match(/whitespace/, body.dig("data", "name").first)
  end

  # Update

  test "update changes content with a version snapshot, renames, and honours expected_version" do
    asset = create("u.md", content: "v1")

    patch "/api/assets/#{asset.slug}", params: { asset: { content: "v2" } }.to_json, headers: headers
    assert_equal 200, response.status
    assert_equal "v2", body.dig("data", "asset", "content")
    assert_equal 1, body.dig("data", "asset", "version")
    assert_equal 1, asset.versions.count

    patch "/api/assets/#{asset.slug}", params: { asset: { name: "new.md" } }.to_json, headers: headers
    assert_equal "new.md", body.dig("data", "asset", "name")
    assert_equal "v2", body.dig("data", "asset", "content")

    patch "/api/assets/#{asset.slug}", params: { asset: { content: "v3", expected_version: 0 } }.to_json, headers: headers
    assert_equal 409, response.status
    assert_equal "version_conflict", body.dig("data", "code")
    assert_equal "v2", asset.reload.content

    patch "/api/assets/00000000", params: { asset: { content: "x" } }.to_json, headers: headers
    assert_equal 404, response.status

    patch "/api/assets/#{asset.slug}", params: { asset: { content: "x" } }.to_json, headers: headers("flk_test_other")
    assert_equal 403, response.status
  end

  # Destroy

  test "destroy archives the asset; 404 unknown; 409 when already archived" do
    asset = create("delete-me.md")

    delete "/api/assets/#{asset.slug}", headers: headers
    assert_equal 200, response.status
    assert body.dig("data", "archived")
    assert asset.reload.deleted_at?

    delete "/api/assets/#{asset.slug}", headers: headers
    assert_equal 409, response.status
    assert_equal "already_archived", body.dig("data", "code")

    delete "/api/assets/00000000", headers: headers
    assert_equal 404, response.status
  end
end
