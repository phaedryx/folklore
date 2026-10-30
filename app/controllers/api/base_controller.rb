module Api
  # JSON API over the same bearer tokens as MCP. No session, no CSRF: every
  # request authenticates itself. Responses follow the {status, data} shape;
  # a failure's data always carries a code and a message (see docs/errors.md).
  class BaseController < ActionController::API
    before_action :authenticate!
    before_action :require_read_scope!, if: -> { request.get? || request.head? }
    before_action :require_write_scope!, unless: -> { request.get? || request.head? }

    rescue_from(*DomainErrors.classes) { |e| render_domain_error(e) }
    rescue_from ActionController::ParameterMissing do |e|
      render_fail({ code: "missing_parameter", message: "#{e.param} is required", e.param => [ "is required" ] })
    end

    private

    attr_reader :current_actor

    def authenticate!
      @current_actor = FolkloreMcp::Authenticate.call(request.headers["Authorization"])
    rescue FolkloreMcp::Authenticate::Error => e
      response.set_header("WWW-Authenticate", "Bearer")
      render_fail({ code: "unauthenticated", message: e.message }, status: :unauthorized)
    end

    def require_read_scope!
      render_forbidden(FolkloreMcp::Tool::READ_SCOPE_ERROR) unless current_actor.token.readable?
    end

    def require_write_scope!
      render_forbidden(FolkloreMcp::Tool::SCOPE_ERROR) unless current_actor.token.writable?
    end

    def render_success(data, status: :ok)
      render status:, json: { status: "success", data: }
    end

    def render_fail(data, status: :unprocessable_content)
      render status:, json: { status: "fail", data: }
    end

    def render_forbidden(message)
      render_fail({ code: "forbidden", message: }, status: :forbidden)
    end

    # The one place the API maps a DomainErrors entry. An input error also
    # names its field, in the {field => [messages]} shape a validation
    # failure has; a validation failure carries every field's messages.
    def render_domain_error(error)
      entry = DomainErrors.for(error)
      message = DomainErrors.message(error)
      data = { code: entry.code, message: }
      data.merge!(entry.field => [ message ]) if entry.field
      data.merge!(error.record.errors.to_hash) if error.is_a?(ActiveRecord::RecordInvalid)
      render_fail(data, status: entry.status)
    end
  end
end
