require "test_helper"

class Markdown::RendererTest < ActiveSupport::TestCase
  URL = ->(asset) { "/member/notes/#{asset.slug}/#{asset.name}" }

  def create(name, content, content_type: nil, path: "member/notes")
    Assets::Create.mutate(actor: actor_for(:member_default), path:, name:, content:, content_type:)
  end

  def render(content, name:, content_type: nil)
    Markdown::Renderer.call(content, content_type:, name:, asset_url: URL)
  end

  test "renders markdown for .md names" do
    rendered = render("# Title\n\nA paragraph with **bold**.", name: "hi.md")

    assert_equal :markdown, rendered.mode
    assert_predicate rendered.html, :html_safe?
    assert_includes rendered.html, "<h1>Title</h1>"
    assert_includes rendered.html, "<strong>bold</strong>"
  end

  test "renders markdown when the content type says so regardless of the name" do
    rendered = render("*em*", name: "notes", content_type: "text/markdown")

    assert_equal :markdown, rendered.mode
    assert_includes rendered.html, "<em>em</em>"
  end

  test "highlights code for known extensions" do
    rendered = render("puts 'hi'", name: "hello.rb")

    assert_equal :code, rendered.mode
    assert_includes rendered.html, %(<span class="nb">puts</span>)
  end

  test "treats a Dockerfile as code" do
    assert_equal :code, render("FROM ruby", name: "Dockerfile").mode
  end

  test "falls back to escaped plain text for unknown extensions" do
    rendered = render("hello <world>", name: "data.unknownext")

    assert_equal :plain, rendered.mode
    assert_includes rendered.html, "hello &lt;world&gt;"
  end

  test "highlights fenced code blocks inside markdown" do
    rendered = render("```ruby\nputs 1\n```\n", name: "a.md")

    assert_includes rendered.html, %(class="highlight)
    assert_includes rendered.html, %(<span class="nb">puts</span>)
  end

  test "[[slug]] becomes a link labelled with the target's current name" do
    target = create("alpha.md", "x")
    rendered = render("See [[#{target.slug}]] for details.", name: "src.md")

    assert_includes rendered.html, %(<a href="/member/notes/#{target.slug}/alpha.md">alpha.md</a>)
  end

  test "[[slug|text]] uses the label" do
    target = create("beta.md", "x")
    rendered = render("Read [[#{target.slug}|the spec]] now.", name: "src.md")

    assert_includes rendered.html, %(<a href="/member/notes/#{target.slug}/beta.md">the spec</a>)
  end

  test "a wikilink in an image src resolves to the asset url" do
    target = create("diagram.png", "x", content_type: "image/png")
    rendered = render("![arch]([[#{target.slug}]])", name: "src.md")

    assert_includes rendered.html, %(<img src="/member/notes/#{target.slug}/diagram.png" alt="arch">)
  end

  test "a wikilink to a missing slug stays literal" do
    rendered = render("Missing: [[zzzzzzzz]] and [[yyyyyyyy|custom]].", name: "src.md")

    assert_includes rendered.html, "[[zzzzzzzz]]"
    assert_includes rendered.html, "[[yyyyyyyy|custom]]"
    assert_not_includes rendered.html, "<a "
  end

  test "wikilinks inside inline code and fences are not expanded" do
    target = create("gamma.md", "x")
    rendered = render("Inline: `[[#{target.slug}]]`\n\n```\n[[#{target.slug}]]\n```\n", name: "src.md")

    assert_equal 2, rendered.html.scan("[[#{target.slug}]]").size
    assert_not_includes rendered.html, "<a "
  end

  test "wikilinks are not expanded outside markdown" do
    target = create("delta.md", "x")

    assert_includes render("See [[#{target.slug}]]", name: "notes.txt").html, "[[#{target.slug}]]"
    assert_includes render("# [[#{target.slug}]]", name: "notes.rb").html, "[[#{target.slug}]]"
  end

  test "raw html and scripts are stripped from markdown" do
    rendered = render("<script>alert(1)</script>\n\n<p onclick=\"x()\">hi</p>\n\n**ok**", name: "a.md")

    assert_not_includes rendered.html, "<script"
    assert_not_includes rendered.html, "onclick"
    assert_includes rendered.html, "<strong>ok</strong>"
  end

  test "javascript: and data: hrefs are stripped, whatever their case or spacing" do
    [ "[x](javascript:alert(1))", "[x](JavaScript:alert(1))", "[x](%6Aavascript:alert(1))",
      "<javascript:alert(1)>", "[x](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)",
      "[x](DATA:text/html,<script>alert(1)</script>)" ].each do |source|
      html = render(source, name: "x.md").html
      fragment = Nokogiri::HTML5.fragment(html)

      fragment.css("a[href]").each do |a|
        refute_match(/\A\s*(javascript|data):/i, a["href"], source)
      end
      refute_match(/javascript:/i, html.gsub("javascript:alert(1)", ""), source) if source.start_with?("<")
    end
  end

  test "data: image sources are stripped" do
    html = render("![i](data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoMSk+)", name: "x.md").html

    Nokogiri::HTML5.fragment(html).css("img").each { |img| refute_match(/\Adata:/i, img["src"].to_s) }
  end

  test "wikilink labels are escaped, resolved or not" do
    target = create("t.md", "x")

    # Entities decode to a literal <img ...> in the text node the wikilink is expanded from.
    resolved = render("[[#{target.slug}|&lt;img src=x onerror=alert(1)&gt;]]", name: "x.md").html
    link = Nokogiri::HTML5.fragment(resolved).at_css("a")
    assert_equal "<img src=x onerror=alert(1)>", link.text
    assert_empty Nokogiri::HTML5.fragment(resolved).css("img")

    dangling = render("[[zzzzzzzz|&lt;script&gt;alert(1)&lt;/script&gt;]]", name: "x.md").html
    assert_empty Nokogiri::HTML5.fragment(dangling).css("script")
    assert_includes dangling, "&lt;script&gt;"
  end

  test "the wikilink pattern is the one the link sync uses" do
    assert_same Markdown::Wikilinks::PATTERN, Markdown::Renderer::WIKILINK
  end
end
