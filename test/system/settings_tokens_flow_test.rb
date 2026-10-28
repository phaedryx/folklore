require "application_system_test_case"

class SettingsTokensFlowTest < ApplicationSystemTestCase
  setup do
    @member = users(:member)
    sign_in(@member, password: "member-secret")
  end

  test "user issues a token for an agent, sees it once, then revokes it" do
    within("[data-testid='primary-nav']") { click_on "Settings" }
    assert_current_path "/settings/tokens"

    click_on "New token"
    fill_in "Agent name", with: "pong"
    click_on "Issue token"

    plaintext = find("[data-testid='token-plaintext']").text.strip
    assert_match(/\Aflk_/, plaintext)
    issued = @member.tokens.find_by!(agent_name: "pong")
    assert_equal Token.digest(plaintext), issued.token_digest

    click_on "Back to tokens"
    assert_selector "[data-testid='token-#{issued.id}']", text: "pong"
    assert_no_text plaintext

    click_on "Revoke pong"
    assert_selector "[data-testid='flash-notice']", text: %(Token "pong" revoked.)
    assert issued.reload.revoked?
  end

  test "a blank agent name shows a validation error" do
    visit "/settings/tokens/new"
    fill_in "Agent name", with: ""
    click_on "Issue token"
    assert_selector "[data-testid='token-errors']", text: "can't be blank"
  end
end
