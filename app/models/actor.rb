# Who is acting: the user, the token they presented (nil for web sessions),
# and the agent label. The agent defaults to the token's name and may be
# overridden per call, but never names a different user.
class Actor < Data.define(:user, :token, :agent)
  WEB_AGENT = "web".freeze

  def self.for_token(token, agent: nil)
    new(user: token.user, token:, agent: agent.presence || token.agent_name)
  end

  def self.for_user(user)
    new(user:, token: nil, agent: WEB_AGENT)
  end

  def handle
    user.handle
  end
end
