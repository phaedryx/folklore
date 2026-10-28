require "test_helper"

class Assets::BrowseTest < ActiveSupport::TestCase
  test "files are the live assets in the dir itself, by name" do
    b = create_asset(path: "member", name: "b.md")
    a = create_asset(path: "member", name: "a.md")
    create_asset(path: "member/notes", name: "deeper.md")
    gone = create_asset(path: "member", name: "gone.md")
    Assets::Delete.mutate(actor: web_actor, slug: gone.slug)

    assert_equal [ a, b ], Assets::Browse.query(dir: "member").files
  end

  test "folders are the next segment of every live dir below, deduped and sorted" do
    create_asset(path: "member/stories/sc-1", name: "x.md")
    create_asset(path: "member/stories/sc-2", name: "y.md")
    create_asset(path: "member/inbox", name: "z.md")
    create_asset(path: "other/notes", name: "o.md", fixture: :other)

    assert_equal %w[inbox stories], Assets::Browse.query(dir: "member").folders
    assert_equal %w[sc-1 sc-2], Assets::Browse.query(dir: "member/stories").folders
  end

  test "a folder holding only archived assets is not shown" do
    gone = create_asset(path: "member/old", name: "x.md")
    Assets::Delete.mutate(actor: web_actor, slug: gone.slug)

    assert_empty Assets::Browse.query(dir: "member").folders
  end

  test "partitions decisions and failures out of the plain files" do
    d = create_asset(path: "member", name: "d.md", tags: [ "decision" ])
    f = create_asset(path: "member", name: "f.md", tags: [ "failure" ])
    n = create_asset(path: "member", name: "n.md", tags: [ "other" ])
    listing = Assets::Browse.query(dir: "member")

    assert_equal [ d ], listing.decisions
    assert_equal [ f ], listing.failures
    assert_equal [ n ], listing.other_files
  end

  test "tasks get their own group, ahead of decisions and failures" do
    t = Tasks::Add.mutate(actor: web_actor, path: "member", name: "t.md", content: "", tags: [ "decision" ])
    d = create_asset(path: "member", name: "d.md", tags: [ "decision" ])
    n = create_asset(path: "member", name: "n.md")
    listing = Assets::Browse.query(dir: "member")

    assert_equal [ t ], listing.tasks
    assert_equal [ d ], listing.decisions
    assert_equal [ n ], listing.other_files
  end

  test "is empty for a dir with nothing in it" do
    listing = Assets::Browse.query(dir: "member/nothing/here")

    assert_predicate listing, :empty?
  end
end
