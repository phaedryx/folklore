require "test_helper"

# A list serialized with Assets::Serializer touches the owner, tags, the
# creating/updating/verifying tokens' users and the task's claimer. These
# pin that the number of queries does not grow with the number of rows.
class SerializedListQueriesTest < ActionDispatch::IntegrationTest
  HEADERS = { "Accept" => "application/json", "Authorization" => "Bearer flk_test_member" }.freeze

  # Keep the once-a-minute last_used_at write out of the counts.
  setup { tokens(:member_default).update_column(:last_used_at, Time.current) }

  def seed(count)
    actor = actor_for(:member_default, agent: "ping")
    Array.new(count) do |i|
      asset = ::Assets::Create.mutate(actor:, path: "member/n#{count}", name: "a#{i}.md", content: "x", tags: [ "t#{i}" ])
      ::Assets::Update.mutate(actor:, slug: asset.slug, content: "y")
      ::Assets::Verify.mutate(actor:, slug: asset.slug)
      ::Tasks::Add.mutate(actor:, path: "member/n#{count}", name: "task#{i}.md", content: "do").tap do |task|
        ::Tasks::Claim.mutate(actor:, slug: task.slug)
      end
      asset
    end
  end

  def index_queries(count)
    seed(count)
    count_queries { get "/api/assets", params: { path: "member/n#{count}" }, headers: HEADERS }
      .tap { assert_response :success }
  end

  test "the API index runs the same number of queries for one row as for four" do
    assert_equal index_queries(1), index_queries(4)
  end

  test "read of an array runs the same number of queries for one slug as for four" do
    counts = [ 1, 4 ].map do |count|
      slugs = seed(count).map(&:slug)
      count_queries do
        response = FolkloreMcp::Tools::Assets::Read.call(ref: slugs, server_context: actor_context)
        refute response.to_h[:isError]
      end
    end

    assert_equal 3, counts.last - counts.first, "only the per-key lookup may repeat"
  end
end
