# The checkpoint domain's errors. The checkpoint's location and the missing
# handle error live on the Checkpoint module (app/models/checkpoint.rb).
module Checkpoints
  Error = Class.new(StandardError)
  EmptyContentError = Class.new(Error)
  NoAgentError = Class.new(Error)
end
