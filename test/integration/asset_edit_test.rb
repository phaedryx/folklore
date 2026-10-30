require "test_helper"

class AssetEditTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  def show_path(asset) = "/#{asset.dir}/#{asset.slug}/#{asset.name}"

  def submit(asset, **fields)
    patch show_path(asset), params: { asset: { name: asset.name, tags: "", content: asset.content,
                                               expected_version: asset.lock_version }.merge(fields) }
  end

  test "the edit form holds the content, name, tags and the version it was read at" do
    asset = create_asset(name: "a.md", content: "body", tags: %w[one two])

    get "#{show_path(asset)}/edit"
    assert_response :success
    assert_select "form[action=?]", show_path(asset) do
      assert_select "input[name='_method'][value=patch]"
      assert_select "textarea[name='asset[content]']", text: "body"
      assert_select "input[name='asset[name]'][value='a.md']"
      assert_select "input[name='asset[tags]'][value='one, two']"
      assert_select "input[type=hidden][name='asset[expected_version]'][value='#{asset.lock_version}']"
    end
  end

  test "saving updates content, name and tags and returns to the show page" do
    asset = create_asset(name: "a.md", content: "v1", tags: %w[old])

    submit(asset, content: "v2", name: "b.md", tags: "new, Fresh")

    asset.reload
    assert_redirected_to "/member/notes/#{asset.slug}/b.md"
    assert_equal "v2", asset.content
    assert_equal "b.md", asset.name
    assert_equal %w[fresh new], asset.tags.map(&:name).sort
    assert_equal "web", asset.updated_by_agent
    assert_equal 1, asset.versions.count
  end

  test "a version conflict saves nothing and re-renders with the current content and the draft" do
    asset = create_asset(name: "a.md", content: "v1")
    stale_version = asset.lock_version
    Assets::Update.mutate(actor: web_actor, slug: asset.slug, content: "theirs")

    submit(asset, content: "mine", expected_version: stale_version)

    assert_response :conflict
    assert_equal "theirs", asset.reload.content
    assert_select "[data-testid='flash-alert']", text: /changed since you opened it/
    assert_select "textarea[name='asset[content]']", text: "theirs"
    assert_select "input[name='asset[expected_version]'][value='#{asset.lock_version}']"
    assert_select "[data-testid='conflict-draft']", text: "mine"
  end

  test "browser line endings do not count as a change" do
    asset = create_asset(name: "a.md", content: "line one\nline two\n")

    submit(asset, content: "line one\r\nline two\r\n")

    assert_equal "line one\nline two\n", asset.reload.content
    assert_equal 0, asset.versions.count
  end

  test "an empty textarea clears the content" do
    asset = create_asset(name: "a.md", content: "something")

    submit(asset, content: "")

    assert_equal "", asset.reload.content
  end

  test "a taken name re-renders the form with the error and the submitted values" do
    create_asset(name: "taken.md")
    asset = create_asset(name: "a.md", content: "v1")

    submit(asset, name: "taken.md", content: "v2")

    assert_response :conflict
    assert_select "[data-testid='error']", text: /already exists/
    assert_select "textarea[name='asset[content]']", text: "v2"
    assert_equal "v1", asset.reload.content
  end

  test "an invalid name re-renders with the error" do
    asset = create_asset(name: "a.md")

    submit(asset, name: "has space.md")

    assert_response :unprocessable_content
    assert_select "[data-testid='error']", text: /whitespace/
  end

  test "another member cannot open or submit the edit form" do
    theirs = create_asset(path: "other/notes", name: "theirs.md", content: "x", fixture: :other)

    get "#{show_path(theirs)}/edit"
    assert_response :forbidden

    submit(theirs, content: "hijack")
    assert_response :forbidden
    assert_equal "x", theirs.reload.content
  end

  test "the new file form creates an asset and shows it" do
    get new_file_path(path: "member/notes")
    assert_select "input[name='asset[path]'][value='member/notes']"

    post files_path, params: { asset: { path: "member/notes", name: "new.md", content: "fresh\r\nline", tags: "a, b" } }

    asset = Asset.live.find_by!(dir: "member/notes", name: "new.md")
    assert_redirected_to show_path(asset)
    assert_equal "fresh\nline", asset.content
    assert_equal %w[a b], asset.tags.map(&:name).sort
  end

  test "creating a duplicate name re-renders the new form with the error" do
    create_asset(name: "dup.md")

    post files_path, params: { asset: { path: "member/notes", name: "dup.md", content: "x" } }

    assert_response :conflict
    assert_select "[data-testid='error']", text: /already exists/
  end

  test "a tag over the length limit re-renders the new form with the error and what was typed" do
    post files_path, params: { asset: { path: "member/notes", name: "t.md", content: "kept", tags: "t" * (Tag::MAX_NAME_LENGTH + 1) } }

    assert_response :unprocessable_content
    assert_select "[data-testid='error']", text: /over the 100 character limit/
    assert_select "textarea[name='asset[content]']", text: "kept"
    assert_nil Asset.live.find_by(dir: "member/notes", name: "t.md")
  end

  test "a name over the length limit re-renders the edit form with the error" do
    asset = create_asset(name: "a.md", content: "v1")

    submit(asset, name: SecureRandom.alphanumeric(Asset::MAX_NAME_LENGTH + 1), content: "v2")

    assert_response :unprocessable_content
    assert_select "[data-testid='error']", text: /over the 255 character limit/
    assert_select "textarea[name='asset[content]']", text: "v2"
    assert_equal "v1", asset.reload.content
  end

  test "creating in a reserved or foreign dir is refused" do
    post files_path, params: { asset: { path: "member/state", name: "x.md", content: "x" } }
    assert_response :unprocessable_content
    assert_select "[data-testid='error']", text: /reserved/

    post files_path, params: { asset: { path: "other/notes", name: "x.md", content: "x" } }
    assert_response :forbidden
  end

  test "archiving returns to the folder and the asset moves to the archive" do
    asset = create_asset(name: "bye.md")

    delete show_path(asset)

    assert_redirected_to "/member/notes"
    assert asset.reload.deleted_at?
    get "/member/archive"
    assert_select "[data-testid='archive-asset-#{asset.slug}']"
  end

  test "restoring from the archive brings it back" do
    asset = create_asset(name: "bye.md")
    Assets::Delete.mutate(actor: web_actor, slug: asset.slug)

    post "/member/archive/#{asset.slug}"

    assert_redirected_to "/member"
    assert_nil asset.reload.deleted_at
  end

  test "restoring onto a taken location explains why" do
    asset = create_asset(name: "bye.md")
    Assets::Delete.mutate(actor: web_actor, slug: asset.slug)
    create_asset(name: "bye.md")

    post "/member/archive/#{asset.slug}"

    assert_redirected_to "/member/archive"
    assert_match(/taken by a live asset/, flash[:alert])
  end

  test "another member cannot archive or restore" do
    theirs = create_asset(path: "other/notes", name: "theirs.md", fixture: :other)

    delete show_path(theirs)
    assert_response :forbidden
    assert_nil theirs.reload.deleted_at

    Assets::Delete.mutate(actor: web_actor(:other), slug: theirs.slug)
    post "/other/archive/#{theirs.slug}"
    assert_response :forbidden
    assert theirs.reload.deleted_at?
  end

  test "archiving twice explains instead of failing" do
    asset = create_asset(name: "bye.md")
    delete show_path(asset)
    delete show_path(asset)

    assert_response :redirect
    assert_match(/already deleted/, flash[:alert])
  end

  test "restoring twice explains instead of failing" do
    asset = create_asset(name: "bye.md")
    Assets::Delete.mutate(actor: web_actor, slug: asset.slug)
    post "/member/archive/#{asset.slug}"
    post "/member/archive/#{asset.slug}"

    assert_redirected_to "/member/archive"
    assert_match(/is not deleted/, flash[:alert])
  end

  test "a conflict keeps the submitted name and tags in the draft" do
    asset = create_asset(name: "a.md", content: "v1", tags: %w[old])
    stale_version = asset.lock_version
    Assets::Update.mutate(actor: web_actor, slug: asset.slug, content: "theirs")

    submit(asset, content: "mine", name: "renamed.md", tags: "new", expected_version: stale_version)

    assert_select "[data-testid='conflict-draft-name']", text: "renamed.md"
    assert_select "[data-testid='conflict-draft-tags']", text: "new"
  end
end
