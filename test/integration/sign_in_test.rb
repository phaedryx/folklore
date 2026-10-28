require "test_helper"

class SignInTest < ActionDispatch::IntegrationTest
  test "the root redirects to sign in when signed out" do
    get "/"

    assert_redirected_to sign_in_path
  end

  test "the sign-in page renders a password form" do
    get sign_in_path

    assert_response :success
    assert_select "input[name=email]"
    assert_select "input[name=password][type=password]"
  end

  test "signing in with the right password reaches the home page" do
    post sign_in_path, params: { email: "Member@Example.com", password: "member-secret" }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_select "[data-testid=current-handle]", text: "member"
  end

  test "a wrong password is rejected and nothing is signed in" do
    post sign_in_path, params: { email: "member@example.com", password: "nope" }

    assert_response :unprocessable_content
    assert_select "[data-testid=flash-alert]", text: /Invalid email or password/

    get "/"
    assert_redirected_to sign_in_path
  end

  test "an unknown email is rejected with the same message" do
    post sign_in_path, params: { email: "ghost@example.com", password: "member-secret" }

    assert_response :unprocessable_content
    assert_select "[data-testid=flash-alert]", text: /Invalid email or password/
  end

  test "a user without a password cannot sign in by password" do
    post sign_in_path, params: { email: "other@example.com", password: "" }

    assert_response :unprocessable_content
  end

  test "the developer strategy signs in an existing user" do
    developer_auth "member@example.com"

    post "/auth/developer/callback"

    assert_redirected_to root_path
    follow_redirect!
    assert_select "[data-testid=current-handle]", text: "member"
  end

  test "the developer strategy refuses an email no user has" do
    developer_auth "ghost@example.com"

    post "/auth/developer/callback"

    assert_redirected_to sign_in_path
    assert_match(/No account for ghost@example.com/, flash[:alert])
    refute User.exists?(email: "ghost@example.com")
  end

  test "auth failure redirects to sign in with the reason" do
    get "/auth/failure", params: { message: "invalid_credentials" }

    assert_redirected_to sign_in_path
    assert_match(/invalid_credentials/, flash[:alert])
  end

  test "signing out ends the session" do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }
    delete sign_out_path

    assert_redirected_to sign_in_path
    get "/"
    assert_redirected_to sign_in_path
  end

  test "the sign-in page redirects home when already signed in" do
    post sign_in_path, params: { email: "member@example.com", password: "member-secret" }

    get sign_in_path

    assert_redirected_to root_path
  end

  test "the health check needs no session" do
    get "/up"

    assert_response :success
  end

  private

  def developer_auth(email)
    OmniAuth.config.mock_auth[:developer] = OmniAuth::AuthHash.new(
      provider: "developer", uid: email, info: { email:, name: "Dev" }
    )
  end
end
