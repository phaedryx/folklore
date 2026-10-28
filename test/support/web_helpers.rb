# Shared setup for component, integration and system tests of the web UI.
module WebTestHelpers
  def web_actor(fixture = :member)
    Actor.for_user(users(fixture))
  end

  def create_asset(path: "member/notes", name: "hello.md", content: "hi", fixture: :member, **rest)
    Assets::Create.mutate(actor: web_actor(fixture), path:, name:, content:, **rest)
  end
end

ActiveSupport::TestCase.include(WebTestHelpers)
ActionDispatch::IntegrationTest.include(WebTestHelpers)
