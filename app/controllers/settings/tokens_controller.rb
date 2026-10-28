module Settings
  class TokensController < ApplicationController
    def index
      @tokens = Tokens::List.query(user: current_user)
    end

    def new
      @agent_name = ""
    end

    def create
      @agent_name = params.require(:token)[:agent_name].to_s
      @result = Tokens::Issue.mutate(user: current_user, agent_name: @agent_name)
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
