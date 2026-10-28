module FolkloreMcp
  module Tools
    module Events
      FolkloreMcp::Tool.user_error(::Events::InvalidTimestampError, "Invalid")
      FolkloreMcp::Tool.user_error(::Events::InvalidCursorError, "Invalid")
    end
  end
end
