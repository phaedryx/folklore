class SessionsController < ApplicationController
  skip_before_action :require_user, only: %i[new create callback failure]

  def new
    redirect_to root_path if signed_in?
  end

  # Password sign-in (single-user mode).
  def create
    user = User.authenticate_by_email(params[:email], params[:password])

    if user
      sign_in(user)
      redirect_to root_path
    else
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  # OmniAuth callback. Only the developer strategy is mounted in phase 1, so
  # this signs in an existing user by email and never creates one. The
  # strategy is mounted at boot; the setting is checked again here so turning
  # it off cannot leave a way in.
  def callback
    unless Rails.configuration.x.developer_sign_in
      return redirect_to sign_in_path, alert: "Developer sign-in is off. Sign in with your email and password."
    end

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
