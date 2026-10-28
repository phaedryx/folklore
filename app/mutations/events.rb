module Events
  Error = Class.new(StandardError)
  InvalidTimestampError = Class.new(Error)
  InvalidCursorError = Class.new(Error)
end
