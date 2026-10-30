require "test_helper"

class Markdown::WikilinksTest < ActiveSupport::TestCase
  test "extracts unique slugs in order of first appearance, with or without labels" do
    text = "see [[abcdefgh]] then [[zzzzzzzz|the other]] and [[abcdefgh]] again"

    assert_equal %w[abcdefgh zzzzzzzz], Markdown::Wikilinks.refs(text)
  end

  test "ignores things that are not eight-character slugs" do
    assert_empty Markdown::Wikilinks.refs("[[not-a-slug]] [[abcdefg]] [[ABCDEFGH]] [[abcdefghi]] [[]]")
  end

  test "ignores slugs with letters generate_slug never uses" do
    assert_empty Markdown::Wikilinks.refs("[[abcdefgi]] [[abcdefgl]] [[abcdefgo]] [[abcdefgu]]")
  end

  test "nil and empty text have no refs" do
    assert_empty Markdown::Wikilinks.refs(nil)
    assert_empty Markdown::Wikilinks.refs("")
  end

  test "the pattern captures slug and label" do
    md = Markdown::Wikilinks::PATTERN.match("[[abcdefgh|a label]]")

    assert_equal "abcdefgh", md[1]
    assert_equal "a label", md[2]
  end
end
