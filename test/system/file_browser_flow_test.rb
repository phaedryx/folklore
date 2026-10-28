require "application_system_test_case"

class FileBrowserFlowTest < ApplicationSystemTestCase
  setup do
    @member = users(:member)
    sign_in(@member, password: "member-secret")
  end

  test "root lists top-level folders and root files" do
    create_asset(path: "member/inbox", name: "a.md", content: "")
    create_asset(path: "member/stories", name: "intro.md", content: "")
    root_note = create_asset(path: "member", name: "readme.md", content: "")

    visit workspace_path("member")

    assert_selector "[data-testid='folder-row-inbox']"
    assert_selector "[data-testid='folder-row-stories']"
    assert_selector "[data-testid='file-row-#{root_note.slug}']", text: "readme.md"
  end

  test "drilling into a folder shows its contents" do
    asset = create_asset(path: "member/stories/sc-1", name: "step.md", content: "")

    visit workspace_path("member")
    click_on "stories"
    click_on "sc-1"

    assert_current_path workspace_path(handle: "member", location: "stories/sc-1")
    assert_selector "[data-testid='file-row-#{asset.slug}']", text: "step.md"
  end

  test "breadcrumb links up the tree" do
    create_asset(path: "member/stories/sc-1", name: "step.md", content: "")

    visit workspace_path(handle: "member", location: "stories/sc-1")

    within "[data-testid='workspace-header']" do
      assert_link "member"
      assert_link "stories"
      assert_link "sc-1"
      click_on "stories"
    end
    assert_current_path workspace_path(handle: "member", location: "stories")
  end

  test "file link goes to the asset show page rendering content" do
    create_asset(path: "member/notes", name: "hi.md", content: "hello")

    visit workspace_path(handle: "member", location: "notes")
    click_on "hi.md"

    assert_selector "[data-testid='asset-content']", text: "hello"
    assert_selector "[data-testid='asset-edit']"
    assert_no_selector "[data-testid='asset-copy']"
    assert_no_selector "[data-testid='asset-alias']"
  end

  test "workspace root shows an Archive folder card for the owner when the archive has items" do
    create_asset(path: "member/inbox", name: "a.md", content: "")
    create_asset(path: "member", name: "readme.md", content: "")
    archived = create_asset(path: "member/inbox", name: "trashed.md", content: "")
    Assets::Delete.mutate(slug: archived.slug, actor: web_actor)

    visit workspace_path("member")
    assert_selector "[data-testid='archive-card-link']"

    last = all("[data-testid='browser-list'] > li").last
    assert_equal "folder-row-archive", last["data-testid"]
  end

  test "archive card is hidden when the archive is empty" do
    create_asset(path: "member", name: "readme.md", content: "")
    visit workspace_path("member")
    assert_no_selector "[data-testid='folder-row-archive']"
  end

  test "archive card is not shown to non-owners viewing someone else's workspace root" do
    asset = create_asset(path: "other/notes", name: "trashed.md", content: "", fixture: :other)
    Assets::Delete.mutate(slug: asset.slug, actor: web_actor(:other))
    create_asset(path: "other", name: "visible.md", content: "", fixture: :other)

    visit workspace_path("other")
    assert_text "visible.md"
    assert_no_selector "[data-testid='folder-row-archive']"
  end

  test "archive card is not shown inside subfolders" do
    asset = create_asset(path: "member/notes", name: "x.md", content: "")
    Assets::Delete.mutate(slug: asset.slug, actor: web_actor)
    create_asset(path: "member/notes", name: "y.md", content: "")
    visit workspace_path(handle: "member", location: "notes")
    assert_no_selector "[data-testid='folder-row-archive']"
  end

  test "clicking the archive card lands on the archive view" do
    archived = create_asset(path: "member/inbox", name: "trashed.md", content: "")
    Assets::Delete.mutate(slug: archived.slug, actor: web_actor)

    visit workspace_path("member")
    find("[data-testid='archive-card-link']").click
    assert_current_path workspace_archive_path("member")
  end

  test "tagged files render tag chips under the name" do
    asset = create_asset(path: "member/notes", name: "tagged.md", content: "", tags: %w[alpha beta])

    visit workspace_path(handle: "member", location: "notes")
    within "[data-testid='file-tags-#{asset.slug}']" do
      assert_selector "[data-testid='tag-chip']", text: "alpha"
      assert_selector "[data-testid='tag-chip']", text: "beta"
    end
  end

  test "decision-tagged files appear in the decisions section" do
    asset = create_asset(path: "member/stories/sc-1", name: "use-resque.md", content: "", tags: [ "decision" ])

    visit workspace_path(handle: "member", location: "stories/sc-1")
    within "[data-testid='workspace-decisions-section']" do
      assert_selector "[data-testid='decision-entry-#{asset.slug}']", text: "use-resque.md"
    end
    assert_no_selector "[data-testid='file-row-#{asset.slug}']"
  end

  test "failure-tagged files appear in the failures section" do
    asset = create_asset(path: "member/stories/sc-1", name: "saml-loop.md", content: "", tags: [ "failure" ])

    visit workspace_path(handle: "member", location: "stories/sc-1")
    within "[data-testid='workspace-failures-section']" do
      assert_selector "[data-testid='failure-entry-#{asset.slug}']", text: "saml-loop.md"
    end
    assert_no_selector "[data-testid='file-row-#{asset.slug}']"
  end

  test "empty folder shows the empty state" do
    visit workspace_path(handle: "member", location: "nothing/here")
    assert_selector "[data-testid='workspace-empty']"
  end

  test "an unknown workspace is a 404" do
    visit workspace_path("ghost")
    assert_text "The page you were looking for doesn"
  end

  test "file card has edit and archive action icons" do
    asset = create_asset(path: "member/notes", name: "x.md", content: "hi")

    visit workspace_path(handle: "member", location: "notes")
    within "[data-testid='file-row-#{asset.slug}']" do
      assert_selector "[data-testid='file-edit-#{asset.slug}']"
      assert_selector "[data-testid='file-archive-#{asset.slug}']"
    end
  end

  test "edit icon opens the plain edit form and saving returns to the file" do
    asset = create_asset(path: "member/notes", name: "edit-me.md", content: "before")

    visit workspace_path(handle: "member", location: "notes")
    find("[data-testid='file-edit-#{asset.slug}']").click
    fill_in "Content", with: "after"
    click_on "Save"

    assert_selector "[data-testid='flash-notice']", text: "Saved."
    assert_selector "[data-testid='asset-content']", text: "after"
  end

  test "archive icon on the card archives the file and removes it from the grid" do
    asset = create_asset(path: "member/notes", name: "trash-me.md", content: "")

    visit workspace_path(handle: "member", location: "notes")
    find("[data-testid='file-archive-#{asset.slug}']").click

    assert_no_selector "[data-testid='file-row-#{asset.slug}']"
  end

  test "action row is hidden entirely on files the viewer doesn't own" do
    asset = create_asset(path: "other/notes", name: "their.md", content: "", fixture: :other)

    visit workspace_path(handle: "other", location: "notes")
    assert_selector "[data-testid='file-row-#{asset.slug}']"
    assert_no_selector "[data-testid='file-actions-#{asset.slug}']"
    assert_no_selector "[data-testid='new-file']"
  end
end
