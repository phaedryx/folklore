class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_user

  rescue_from(*DomainErrors.classes) { |e| render_domain_error(e, DomainErrors.for(e)) }

  private

  # The one place the web maps a DomainErrors entry: the 404 or 403 page, or
  # back with the message as the alert. A GET goes to the page's own default
  # rather than the referrer, so a bad filter cannot redirect to itself.
  # Controllers with a form override this to re-render it, keeping what was
  # typed, and call super for everything else.
  def render_domain_error(error, entry)
    case entry.status
    when :not_found then not_found
    when :forbidden then forbidden
    else
      alert = DomainErrors.message(error)
      if request.get?
        redirect_to error_fallback_location, alert:
      else
        redirect_back_or_to error_fallback_location, alert:
      end
    end
  end

  # Where an error redirects when there is no referrer, or the request was a
  # GET.
  def error_fallback_location
    root_path
  end

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
