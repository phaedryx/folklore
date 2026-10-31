# Who is acting: the user, the token they presented (nil for web sessions),
# and the agent label. The agent defaults to the token's name. A shared token
# may override it per call; the override never names a different user.
class Actor < Data.define(:user, :token, :agent)
  InvalidAgentError = Class.new(StandardError)

  WEB_AGENT = "web".freeze
  # Agent labels become path segments (checkpoints) and claim identities, so
  # they are lowercase slugs: no dots, no slashes, no whitespace, no case.
  AGENT_REGEX = /\A[a-z0-9][a-z0-9_-]{0,63}\z/

  def self.for_token(token, agent: nil)
    agent = validate_agent!(agent.to_s.strip.presence || token.agent_name)
    if agent != token.agent_name && !token.shared?
      raise InvalidAgentError, "token #{token.agent_name.inspect} is not shared, so it acts only as #{token.agent_name.inspect}; " \
                               "issue a shared token to pass agent"
    end

    new(user: token.user, token:, agent:)
  end

  def self.validate_agent!(agent)
    raise InvalidAgentError, "agent #{agent.inspect} must match #{AGENT_REGEX.inspect}" unless agent.match?(AGENT_REGEX)
    raise InvalidAgentError, "agent #{WEB_AGENT.inspect} is reserved for web sessions" if agent == WEB_AGENT

    agent
  end

  def self.for_user(user)
    new(user:, token: nil, agent: WEB_AGENT)
  end

  # How an actor is written everywhere it is shown: "handle/agent".
  def self.label(handle, agent)
    "#{handle}/#{agent}"
  end

  def handle
    user.handle
  end

  def label
    Actor.label(handle, agent)
  end
end
