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

  test "a new token gets both scopes by default, and read only when write is unchecked" do
    get new_settings_token_path
    assert_select "input[type=checkbox][name='token[scopes][]'][value=read][checked]"
    assert_select "input[type=checkbox][name='token[scopes][]'][value=write][checked]"

    post settings_tokens_path, params: { token: { agent_name: "both", scopes: %w[read write] } }
    assert_equal %w[read write], users(:member).tokens.find_by!(agent_name: "both").scopes

    post settings_tokens_path, params: { token: { agent_name: "reader2", scopes: %w[read] } }
    assert_equal %w[read], users(:member).tokens.find_by!(agent_name: "reader2").scopes

    get settings_tokens_path
    assert_select "[data-testid='token-#{users(:member).tokens.find_by!(agent_name: "reader2").id}']", text: /read\b(?!, write)/
  end

  test "a new token is not shared unless the box is checked, and the list says which are" do
    get new_settings_token_path
    assert_select "input[type=checkbox][name='token[shared]']:not([checked])"

    post settings_tokens_path, params: { token: { agent_name: "solo", shared: "0" } }
    refute_predicate users(:member).tokens.find_by!(agent_name: "solo"), :shared?

    post settings_tokens_path, params: { token: { agent_name: "team", shared: "1" } }
    team = users(:member).tokens.find_by!(agent_name: "team")
    assert_predicate team, :shared?

    get settings_tokens_path
    assert_select "[data-testid='token-#{team.id}'] [data-testid='token-shared']", text: /shared/
    assert_select "[data-testid='token-#{users(:member).tokens.find_by!(agent_name: "solo").id}'] [data-testid='token-shared']", false
  end

  test "a shared box left checked survives a re-rendered form" do
    post settings_tokens_path, params: { token: { agent_name: "Not A Slug", shared: "1" } }

    assert_response :unprocessable_content
    assert_select "input[type=checkbox][name='token[shared]'][checked]"
  end

  test "no scopes re-renders the form with the error" do
    post settings_tokens_path, params: { token: { agent_name: "none", scopes: [ "" ] } }

    assert_response :unprocessable_content
    assert_select "[data-testid='token-errors']", text: /Scopes/
    assert_select "input[type=checkbox][name='token[scopes][]'][value=write]:not([checked])"
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

  test "revoking a revoked token says so" do
    delete settings_token_path(tokens(:member_revoked))

    assert_redirected_to settings_tokens_path
    follow_redirect!
    assert_select "[data-testid='flash-alert']", text: /already revoked/
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
