module FolkloreMcp
  module Tools
    module Tags
      FolkloreMcp::Tool.user_error(::Tags::NotFoundError, "Not found")
      FolkloreMcp::Tool.user_error(::Tags::ForbiddenError, "Forbidden")
      FolkloreMcp::Tool.user_error(::Tags::AlreadyAppliedError, "Conflict")
      FolkloreMcp::Tool.user_error(::Tags::NotAppliedError, "Not found")
      FolkloreMcp::Tool.user_error(::Tags::InvalidTagError, "Invalid")
    end
  end
end
