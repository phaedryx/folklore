# The session checkpoint: one reserved asset per (user, agent) holding "where
# I left off", so an agent resumes with a single read.
#
# Not an ActiveRecord model; a checkpoint is an ordinary Asset at a reserved
# location. This is the one place that location is spelled out.
module Checkpoint
  NoHandleError = Class.new(StandardError)

  SEGMENT = "state".freeze
  NAME = "last_session.md".freeze

  # The directory of the actor's checkpoint, e.g. "member/state/ping".
  def self.dir_for(actor)
    handle = actor&.handle
    raise NoHandleError, "actor has no handle; claim one before using checkpoints" if handle.blank?

    "#{handle}/#{SEGMENT}/#{actor.agent}"
  end
end
