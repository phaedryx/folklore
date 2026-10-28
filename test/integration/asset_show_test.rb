require "test_helper"

class AssetShowTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  def show_path(asset) = "/#{asset.dir}/#{asset.slug}/#{asset.name}"

  test "renders markdown content as HTML for .md files" do
    asset = create_asset(name: "hi.md", content: "# Title\n\nA paragraph with **bold**.")

    get show_path(asset)
    assert_response :success
    assert_select "[data-testid='asset-content'][data-render='markdown']"
    assert_select "[data-testid='asset-content'] h1", text: "Title"
    assert_select "[data-testid='asset-content'] strong", text: "bold"
  end

  test "renders code with syntax highlighting for known extensions" do
    asset = create_asset(path: "member/code", name: "hello.rb", content: "puts 'hi'")

    get show_path(asset)
    assert_select "[data-testid='asset-content'][data-render='code']"
    assert_select "[data-testid='asset-content'] pre code"
  end

  test "falls back to plain pre for unknown extensions" do
    asset = create_asset(path: "member/blob", name: "data.unknownext", content: "hello world")

    get show_path(asset)
    assert_select "[data-testid='asset-content'][data-render='plain']", text: "hello world"
  end

  test "an asset at the workspace root has a show page" do
    asset = create_asset(path: "member", name: "readme.md", content: "root body")

    get "/member/#{asset.slug}/readme.md"
    assert_select "[data-testid='asset-content']", text: /root body/
  end

  test "raw=true returns the unformatted content with no layout" do
    asset = create_asset(name: "hi.md", content: "# Title\n\nbody")

    get "#{show_path(asset)}?raw=true"
    assert_response :success
    assert_equal "# Title\n\nbody", response.body
    assert_no_match(/<html/i, response.body)
  end

  test "raw=true honors the asset content_type when present" do
    asset = create_asset(path: "member/blob", name: "thing.json", content: "{\"a\":1}", content_type: "application/json")

    get "#{show_path(asset)}?raw=true"
    assert_equal "{\"a\":1}", response.body
    assert_match %r{application/json}, response.content_type
  end

  test "raw=true sandboxes the response so stored html cannot run script on this origin" do
    asset = create_asset(path: "member/blob", name: "page.html", content: "<script>alert(1)</script>", content_type: "text/html")

    get "#{show_path(asset)}?raw=true"
    assert_equal "sandbox", response.headers["Content-Security-Policy"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "a stale name or dir in the url redirects to the canonical address" do
    asset = create_asset(name: "hi.md")

    get "/member/elsewhere/#{asset.slug}/old-name.md"
    assert_redirected_to show_path(asset)
    assert_response :found
  end

  test "an unknown slug is a 404" do
    get "/member/notes/zzzzzzzz/nope.md"
    assert_response :not_found
  end

  test "an archived asset is a 404" do
    asset = create_asset(name: "gone.md")
    Assets::Delete.mutate(actor: web_actor, slug: asset.slug)

    get show_path(asset)
    assert_response :not_found
  end

  test "[[SLUG]] expands to a link using the target's current name" do
    target = create_asset(name: "alpha.md", content: "x")
    source = create_asset(name: "src.md", content: "See [[#{target.slug}]] for details.")

    get show_path(source)
    assert_select "[data-testid='asset-content'] a[href=?]", show_path(target), text: "alpha.md"
  end

  test "[[SLUG|text]] uses the override text as the link label" do
    target = create_asset(name: "beta.md", content: "x")
    source = create_asset(name: "src.md", content: "Read [[#{target.slug}|the spec]] now.")

    get show_path(source)
    assert_select "[data-testid='asset-content'] a[href=?]", show_path(target), text: "the spec"
  end

  test "wikilink in image src position resolves to the asset URL" do
    target = create_asset(path: "member/img", name: "diagram.png", content: "x", content_type: "image/png")
    source = create_asset(name: "src.md", content: "![arch]([[#{target.slug}]])")

    get show_path(source)
    assert_select "img[src=?][alt=?]", show_path(target), "arch"
  end

  test "broken slug is left as a literal wikilink" do
    source = create_asset(name: "src.md", content: "Missing: [[zzzzzzzz]] and [[yyyyyyyy|custom]].")

    get show_path(source)
    text = css_select("[data-testid='asset-content']").text
    assert_match "[[zzzzzzzz]]", text
    assert_match "[[yyyyyyyy|custom]]", text
  end

  test "wikilinks inside inline code and fenced code blocks are not expanded" do
    target = create_asset(name: "gamma.md", content: "x")
    source = create_asset(name: "src.md", content: "Inline: `[[#{target.slug}]]`\n\n```\n[[#{target.slug}]]\n```\n")

    get show_path(source)
    body = css_select("[data-testid='asset-content']").to_s
    assert_match "[[#{target.slug}]]", body
    assert_no_match %r{<a href="[^"]+">\[\[#{target.slug}\]\]</a>}, body
  end

  test "wikilinks are not expanded in plain text (non-markdown) renders" do
    target = create_asset(name: "delta.md", content: "x")
    source = create_asset(path: "member/blob", name: "notes.txt", content: "See [[#{target.slug}]]")

    get show_path(source)
    assert_select "[data-testid='asset-content'][data-render='plain']", text: /\[\[#{target.slug}\]\]/
  end

  test "show page does not render tag chips" do
    asset = create_asset(name: "tagged.md", content: "body", tags: %w[alpha beta])

    get show_path(asset)
    assert_select "[data-testid='asset-content']"
    assert_select "[data-testid='tag-chip']", false, "show page should not render tag chips"
  end

  test "the backlinks panel lists live assets that link here" do
    target = create_asset(name: "target.md", content: "x")
    linking = create_asset(path: "member/ideas", name: "linker.md", content: "see [[#{target.slug}]]")
    gone = create_asset(name: "gone.md", content: "also [[#{target.slug}]]")
    Assets::Delete.mutate(actor: web_actor, slug: gone.slug)

    get show_path(target)
    assert_select "[data-testid='backlinks'] [data-testid='backlink-#{linking.slug}'] a[href=?]", show_path(linking), text: "linker.md"
    assert_select "[data-testid='backlink-#{gone.slug}']", false
  end

  test "no backlinks panel when nothing links here" do
    asset = create_asset(name: "lonely.md")

    get show_path(asset)
    assert_select "[data-testid='backlinks']", false
  end

  test "the owner sees edit, verify and archive; download is for everyone" do
    asset = create_asset(name: "mine.md")

    get show_path(asset)
    assert_select "[data-testid='asset-download'][href=?]", "#{show_path(asset)}?raw=true"
    assert_select "[data-testid='asset-edit'][href=?]", "#{show_path(asset)}/edit"
    assert_select "form[action=?] [data-testid='asset-verify']", "/verifications/#{asset.slug}"
    assert_select "form[action=?] [data-testid='asset-archive']", show_path(asset)
  end

  test "another member sees no write affordances" do
    theirs = create_asset(path: "other/notes", name: "theirs.md", fixture: :other)

    get show_path(theirs)
    assert_response :success
    assert_select "[data-testid='asset-download']"
    assert_select "[data-testid='asset-edit']", false
    assert_select "[data-testid='asset-verify']", false
    assert_select "[data-testid='asset-archive']", false
  end

  test "an overdue asset is flagged" do
    asset = create_asset(name: "old.md")
    Assets::SetStaleAfter.mutate(actor: web_actor, slug: asset.slug, stale_after: Date.current - 3)

    get show_path(asset)
    assert_select "[data-testid='asset-stale']"
  end

  test "signed out is sent to sign in" do
    asset = create_asset(name: "hi.md")
    delete sign_out_path

    get show_path(asset)
    assert_redirected_to sign_in_path
  end
end
