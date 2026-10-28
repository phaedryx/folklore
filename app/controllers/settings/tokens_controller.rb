module Settings
  class TokensController < ApplicationController
    def index
      @tokens = Tokens::List.query(user: current_user)
    end

    def new
      @agent_name = ""
      @scopes = Token::SCOPES
    end

    def create
      attrs = params.require(:token).permit(:agent_name, scopes: [])
      @agent_name = attrs[:agent_name].to_s
      # The form always submits scopes (a blank hidden field when every box is
      # unchecked); a request without the key gets both.
      @scopes = attrs.key?(:scopes) ? Array(attrs[:scopes]).compact_blank : Token::SCOPES
      @result = Tokens::Issue.mutate(user: current_user, agent_name: @agent_name, scopes: @scopes)
      render :issued
    rescue ActiveRecord::RecordInvalid => e
      @errors = e.record.errors.full_messages
      render :new, status: :unprocessable_content
    end

    def destroy
      token = Tokens::List.query(user: current_user).find(params[:id])
      Tokens::Revoke.mutate(token:, actor: current_actor)
      redirect_to settings_tokens_path, notice: %(Token "#{token.agent_name}" revoked.)
    rescue Tokens::Revoke::AlreadyRevokedError
      redirect_to settings_tokens_path, alert: %(Token "#{token.agent_name}" was already revoked.)
    end
  end
end
