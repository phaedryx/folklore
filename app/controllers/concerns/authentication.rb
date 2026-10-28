# Session-cookie authentication for the web UI. MCP and API requests carry a
# bearer token instead and never touch the session.
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_user
    helper_method :current_user, :signed_in?, :current_actor
  end

  private

  def set_current_user
    Current.user = User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_user
    Current.user
  end

  # Web writes act as the signed-in user with the reserved `web` agent.
  def current_actor
    Actor.for_user(current_user) if current_user
  end

  def signed_in?
    current_user.present?
  end

  def require_user
    redirect_to sign_in_path unless signed_in?
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    Current.user = user
  end

  def sign_out
    reset_session
    Current.user = nil
  end
end
