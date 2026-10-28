require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include WebTestHelpers

  # The pages are server-rendered forms and links, so rack_test drives them
  # without a browser. Switch a test to :selenium_chrome_headless if it ever
  # needs JavaScript.
  driven_by :rack_test

  private

  # Members with a password sign in through the password form; the rest use
  # the developer strategy, which test mode answers from mock_auth.
  def sign_in(user, password: nil)
    visit sign_in_path
    if password
      fill_in "Email", with: user.email
      fill_in "Password", with: password
      click_on "Sign in"
    else
      OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
        provider: "developer", uid: user.email, info: { email: user.email, name: user.name }
      )
      within("form[action='/auth/developer/callback']") do
        find("input[name=email]").set(user.email)
        click_on "Go"
      end
    end
    assert_selector "[data-testid='primary-nav']"
  end
end
