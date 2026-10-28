require "test_helper"

class Tags::ListTest < ActiveSupport::TestCase
  def create(name, path: "member/notes", tags: [])
    Assets::Create.mutate(actor: actor_for(:member_default), path:, name:, content: "", tags:)
  end

  test "returns each tag on live assets with its count, by count desc then name" do
    create("a.md", tags: %w[zebra apple])
    create("b.md", tags: %w[zebra apple])
    create("c.md", tags: %w[banana])

    assert_equal [ [ "apple", 2 ], [ "zebra", 2 ], [ "banana", 1 ] ], Tags::List.query
  end

  test "excludes deleted assets and drops tags only they carried" do
    gone = create("gone.md", tags: %w[shell orphan])
    create("present.md", tags: %w[shell])
    gone.update!(deleted_at: Time.current)

    assert_equal [ [ "shell", 1 ] ], Tags::List.query
  end

  test "within scopes counts to a dir subtree" do
    create("in.md", tags: %w[shell])
    create("nested.md", path: "member/notes/sub", tags: %w[shell])
    create("out.md", path: "member/scripts", tags: %w[shell])

    assert_equal [ [ "shell", 2 ] ], Tags::List.query(within: "member/notes")
  end

  test "returns empty when nothing is tagged" do
    create("untagged.md")

    assert_equal [], Tags::List.query
  end
end
