module Tags
  Error = Class.new(StandardError)
  NotFoundError = Class.new(Error)
  ForbiddenError = Class.new(Error)
  AlreadyAppliedError = Class.new(Error)
  NotAppliedError = Class.new(Error)
  InvalidTagError = Class.new(Error)
end
