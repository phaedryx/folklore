# The session checkpoint: one reserved asset per (user, token, agent) holding
# "where I left off", so an agent resumes with a single read.
#
# Not an ActiveRecord model; a checkpoint is an ordinary Asset at a reserved
# location. This is the one place that location is spelled out.
module Checkpoint
  NoHandleError = Class.new(StandardError)

  SEGMENT = "state".freeze
  NAME = "last_session.md".freeze

  # The directory of the actor's checkpoint. A token's own agent keeps it at
  # "member/state/ci". An agent a shared token names with `agent` keeps it
  # under the token, "member/state/team/ping", so no name a token passes can
  # reach another token's checkpoint. Keyed by the token's name rather than its
  # id, so a reissued token picks up where the revoked one left off.
  def self.dir_for(actor)
    handle = actor&.handle
    raise NoHandleError, "actor has no handle; claim one before using checkpoints" if handle.blank?

    token_name = actor.token&.agent_name
    return "#{handle}/#{SEGMENT}/#{actor.agent}" if token_name.nil? || token_name == actor.agent

    "#{handle}/#{SEGMENT}/#{token_name}/#{actor.agent}"
  end
end
