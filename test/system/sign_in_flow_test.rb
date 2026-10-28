require "application_system_test_case"

class SignInFlowTest < ApplicationSystemTestCase
  test "unauthenticated request to / redirects to sign-in" do
    visit "/"
    assert_current_path "/sign_in"
  end

  test "a member signs in with a password and lands on home" do
    visit "/"
    fill_in "Email", with: "member@example.com"
    fill_in "Password", with: "member-secret"
    click_on "Sign in"

    assert_current_path "/"
    assert_selector "[data-testid='current-handle']", text: "member"
    click_on "Browse your workspace"
    assert_current_path "/member"
  end

  test "a wrong password stays on sign-in with an alert" do
    visit "/sign_in"
    fill_in "Email", with: "member@example.com"
    fill_in "Password", with: "wrong"
    click_on "Sign in"

    assert_selector "[data-testid='flash-alert']", text: "Invalid email or password."
    assert_no_selector "[data-testid='primary-nav']"
  end

  test "signing out returns to sign-in" do
    sign_in users(:member), password: "member-secret"
    click_on "Sign out"

    assert_current_path "/sign_in"
    assert_selector "[data-testid='flash-notice']", text: "Signed out."
  end
end
