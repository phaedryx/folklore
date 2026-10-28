class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_user

  rescue_from ActiveRecord::RecordNotFound, Assets::NotFoundError, Versions::NotFoundError, with: :not_found
  rescue_from Assets::ForbiddenError, with: :forbidden

  private

  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end

  def forbidden
    render file: Rails.public_path.join("403.html"), status: :forbidden, layout: false
  end

  # Browsers submit textareas with CRLF line endings; stored content uses LF,
  # so an unchanged textarea must not read as an edit.
  def normalize_newlines(text)
    text&.gsub("\r\n", "\n")
  end

  def parse_tags(raw)
    raw.to_s.split(",").map(&:strip).reject(&:empty?)
  end
end
