require "test_helper"

class SettingsTokensTest < ActionDispatch::IntegrationTest
  setup do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
  end

  test "lists only my tokens, with agent name and status" do
    get settings_tokens_path
    assert_response :success
    assert_select "[data-testid='token-#{tokens(:member_default).id}']", text: /default/
    assert_select "[data-testid='token-#{tokens(:member_revoked).id}']", text: /revoked/
    assert_select "[data-testid='token-#{tokens(:other_default).id}']", false
  end

  test "issuing shows the plaintext once with an MCP config snippet" do
    post settings_tokens_path, params: { token: { agent_name: "ping" } }

    assert_response :success
    plaintext = css_select("[data-testid='token-plaintext']").first.text.strip
    assert_match(/\Aflk_\w{32}\z/, plaintext)
    token = users(:member).tokens.find_by!(agent_name: "ping")
    assert_equal Token.digest(plaintext), token.token_digest
    assert_select "[data-testid='token-mcp-config']", text: /"Authorization": "Bearer #{plaintext}"/

    get settings_tokens_path
    assert_no_match plaintext, response.body
  end

  test "an invalid agent name re-renders the form with the error" do
    post settings_tokens_path, params: { token: { agent_name: "Not A Slug" } }

    assert_response :unprocessable_content
    assert_select "[data-testid='token-errors']", text: /lowercase slug/
    assert_select "input[name='token[agent_name]'][value='Not A Slug']"
  end

  test "web is reserved for the browser session" do
    post settings_tokens_path, params: { token: { agent_name: "web" } }

    assert_response :unprocessable_content
    assert_select "[data-testid='token-errors']", text: /reserved/
  end

  test "revoking marks the token revoked" do
    token = tokens(:member_default)

    delete settings_token_path(token)

    assert_redirected_to settings_tokens_path
    assert_predicate token.reload, :revoked?
    follow_redirect!
    assert_select "[data-testid='flash-notice']", text: /default/
  end

  test "another member's token cannot be revoked" do
    token = tokens(:other_default)

    delete settings_token_path(token)

    assert_response :not_found
    assert_not_predicate token.reload, :revoked?
  end

  test "settings root redirects to tokens" do
    get "/settings"
    assert_redirected_to "/settings/tokens"
  end
end
