module Api
  # JSON API over the same bearer tokens as MCP. No session, no CSRF: every
  # request authenticates itself. Responses follow the {status, data} shape.
  class BaseController < ActionController::API
    before_action :authenticate!

    rescue_from ::Assets::NotFoundError, with: -> { render_not_found }
    rescue_from ::Assets::ForbiddenError, with: ->(e) { render_forbidden(e.message) }
    rescue_from ::Assets::NameTakenError, with: -> { render_fail({ name: [ "already taken at this path" ] }) }
    rescue_from ::Assets::ConflictError, with: ->(e) { render_fail({ code: "version_conflict", message: e.message }, status: :conflict) }
    rescue_from ::Assets::AlreadyDeletedError, with: -> { render_fail({ code: "already_archived" }, status: :conflict) }
    rescue_from ::Assets::NotDeletedError, with: -> { render_fail({ code: "not_archived" }, status: :conflict) }
    rescue_from ::Asset::InvalidDirError, with: ->(e) { render_fail({ path: [ e.message ] }) }
    rescue_from ::Asset::InvalidNameError, with: ->(e) { render_fail({ name: [ e.message ] }) }
    rescue_from ::Asset::InvalidStaleAfterError, with: ->(e) { render_fail({ stale_after: [ e.message ] }) }
    rescue_from ::Asset::ContentTooLargeError, with: ->(e) { render_fail({ content: [ e.message ] }) }
    rescue_from ActiveRecord::RecordInvalid, with: ->(e) { render_fail(e.record.errors.as_json) }
    rescue_from ActionController::ParameterMissing, with: ->(e) { render_fail({ e.param => [ "is required" ] }) }

    private

    attr_reader :current_actor

    def authenticate!
      @current_actor = FolkloreMcp::Authenticate.call(request.headers["Authorization"])
    rescue FolkloreMcp::Authenticate::Error => e
      response.set_header("WWW-Authenticate", "Bearer")
      render status: :unauthorized,
             json: { status: "fail", data: { resource: "unauthenticated", message: e.message } }
    end

    def render_success(data, status: :ok)
      render status:, json: { status: "success", data: }
    end

    def render_fail(data, status: :unprocessable_entity)
      render status:, json: { status: "fail", data: }
    end

    def render_not_found(resource = "asset")
      render status: :not_found, json: { status: "fail", data: { resource: "#{resource}_not_found" } }
    end

    def render_forbidden(message)
      render status: :forbidden, json: { status: "fail", data: { base: [ message ] } }
    end
  end
end
