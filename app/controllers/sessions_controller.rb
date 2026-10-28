class SessionsController < ApplicationController
  skip_before_action :require_user, only: %i[new create callback failure]

  def new
    redirect_to root_path if signed_in?
  end

  # Password sign-in (single-user mode).
  def create
    user = User.find_by("lower(email) = ?", params[:email].to_s.downcase.strip)

    if user&.password_digest.present? && user.authenticate(params[:password].to_s)
      sign_in(user)
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  # OmniAuth callback. Only the developer strategy is mounted in phase 1, so
  # this signs in an existing user by email and never creates one.
  def callback
    auth = request.env["omniauth.auth"]
    email = auth&.dig("info", "email").to_s.downcase.strip
    user = User.find_by("lower(email) = ?", email) if email.present?

    if user
      sign_in(user)
      redirect_to root_path
    else
      redirect_to sign_in_path, alert: "No account for #{email.presence || 'that email'}. Run bin/setup to create one."
    end
  end

  def destroy
    sign_out
    redirect_to sign_in_path, notice: "Signed out."
  end

  def failure
    redirect_to sign_in_path, alert: "Sign-in failed: #{params[:message] || 'unknown error'}"
  end
end
