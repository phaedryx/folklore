require "test_helper"

# The feed renders every action through one component, and Events::List has
# no action filter, so an action the component cannot draw would break
# /activity for anyone who triggered it.
class ActivityFeedTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  def event_ids
    css_select("[data-testid^='activity-']").filter_map { |el| el["data-testid"][/\Aactivity-(\d+)\z/, 1]&.to_i }
  end

  test "every event action renders" do
    asset = create_asset(name: "n.md")
    Event::ACTIONS.each { |action| Events::Record.mutate(actor: web_actor, asset:, action:, metadata: { "reason" => "why" }) }

    get activity_path
    assert_response :success
    Event::ACTIONS.each { |action| assert_select "[data-testid^='activity-action-']", text: action }
  end

  test "renders an asset_verified entry" do
    asset = create_asset(name: "n.md")
    Assets::Verify.mutate(slug: asset.slug, actor: web_actor)
    event = Event.where(asset_id: asset.id, action: "asset_verified").sole

    get activity_path
    assert_select "[data-testid='activity-#{event.id}']"
    assert_select "[data-testid='activity-action-#{event.id}']", text: "asset_verified"
  end

  test "newest first, a page at a time, with an older link by id" do
    asset = create_asset(name: "n.md")
    stub_const(EventsController, :PAGE_SIZE, 3) do
      5.times { Events::Record.mutate(actor: web_actor, asset:, action: "asset_updated") }
      all_ids = Event.order(id: :desc).pluck(:id)

      get activity_path
      assert_equal all_ids.first(3), event_ids
      older = css_select("[data-testid='activity-older']").first["href"]
      assert_equal activity_path(before_id: all_ids[2]), older

      get older
      assert_equal all_ids[3, 3], event_ids
    end
  end

  test "since_id shows what happened after a cursor, newest first, with a newer link" do
    asset = create_asset(name: "n.md")
    cursor = Event.maximum(:id)
    stub_const(EventsController, :PAGE_SIZE, 2) do
      3.times { Events::Record.mutate(actor: web_actor, asset:, action: "asset_updated") }
      after = Event.where("id > ?", cursor).order(:id).pluck(:id)

      get activity_path(since_id: cursor)
      assert_equal after.first(2).reverse, event_ids
      newer = css_select("[data-testid='activity-newer']").first["href"]
      assert_equal activity_path(since_id: after[1]), newer

      get newer
      assert_equal [ after[2] ], event_ids
    end
  end

  test "filters by actor and tag, and the pager keeps the filters" do
    tagged = create_asset(name: "t.md", tags: %w[shell])
    create_asset(name: "u.md")
    create_asset(path: "other/notes", name: "o.md", fixture: :other, tags: %w[shell])

    get activity_path(actor: "member", tag: "shell")
    assert_select "[data-testid^='activity-asset-']", count: 1
    assert_select "[data-testid^='activity-asset-']", text: tagged.name
    assert_select "input[name=actor][value=member]"
    assert_select "input[name=tag][value=shell]"
    assert_select "[data-testid='filter-clear']"
  end

  test "a non-numeric since_id or before_id redirects to the feed with an alert" do
    %w[since_id before_id].each do |param|
      get activity_path, params: { param => "abc", actor: "member" }

      assert_redirected_to activity_path(actor: "member")
      follow_redirect!
      assert_select "[data-testid='flash-alert']", text: /#{param} must be a non-negative integer/
    end
  end

  test "shows the empty state when nothing matches" do
    get activity_path(actor: "ghost")
    assert_select "[data-testid='activity-empty']"
  end

  private

  def stub_const(klass, name, value)
    old = klass.const_get(name)
    klass.send(:remove_const, name)
    klass.const_set(name, value)
    yield
  ensure
    klass.send(:remove_const, name)
    klass.const_set(name, old)
  end
end
