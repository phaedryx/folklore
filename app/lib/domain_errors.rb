# Every error a caller can act on, defined once: a stable `code`, the HTTP
# `status` it means, and for an error about one input, the API `field` it
# belongs to. Each transport maps an entry once and nowhere else:
#
# - MCP (FolkloreMcp::Tool.call): "<prefix>: <message>", the prefix chosen by
#   status, with a few task-queue codes named for themselves.
# - JSON API (Api::BaseController): the status, and data carrying the code,
#   the message and, for a field error, `{field => [message]}`.
# - Web (ApplicationController): a 404 or 403 page, otherwise a redirect
#   with the message as the alert. Form actions re-render the form instead.
#
# An unregistered error is a bug: MCP answers "Internal error", the API and
# web a 500. docs/errors.md lists every code; a test keeps it complete.
module DomainErrors
  Entry = Data.define(:code, :status, :field)

  def self.entry(code, status, field = nil) = Entry.new(code:, status:, field:)
  private_class_method :entry

  ENTRIES = {
    # Generic record failures that escape a mutation.
    ActiveRecord::RecordNotFound => entry("not_found", :not_found),
    ActiveRecord::RecordInvalid => entry("invalid", :unprocessable_content),
    ActiveRecord::StaleObjectError => entry("version_conflict", :conflict),

    # Assets
    Assets::NotFoundError => entry("not_found", :not_found),
    Assets::ForbiddenError => entry("forbidden", :forbidden),
    Assets::NameTakenError => entry("name_taken", :conflict, :name),
    Assets::ConflictError => entry("version_conflict", :conflict),
    Assets::AlreadyDeletedError => entry("already_archived", :conflict),
    Assets::NotDeletedError => entry("not_archived", :conflict),
    Assets::NotANoteError => entry("not_a_note", :unprocessable_content),
    Assets::InvalidStatusError => entry("invalid_status", :unprocessable_content, :status),
    Assets::InvalidLocationError => entry("invalid_location", :unprocessable_content, :location),
    Assets::Search::InvalidArgumentError => entry("invalid_argument", :unprocessable_content),
    Asset::InvalidNameError => entry("invalid_name", :unprocessable_content, :name),
    Asset::InvalidDirError => entry("invalid_path", :unprocessable_content, :path),
    Asset::ReservedDirError => entry("reserved_path", :unprocessable_content, :path),
    Asset::InvalidStaleAfterError => entry("invalid_stale_after", :unprocessable_content, :stale_after),
    Asset::ContentTooLargeError => entry("content_too_large", :unprocessable_content, :content),
    Versions::NotFoundError => entry("version_not_found", :not_found),

    # Tags. Tags::InvalidTagError is Tag::InvalidNameError.
    Tags::NotFoundError => entry("not_found", :not_found),
    Tags::ForbiddenError => entry("forbidden", :forbidden),
    Tags::AlreadyAppliedError => entry("tag_already_applied", :conflict),
    Tags::NotAppliedError => entry("tag_not_applied", :not_found),
    Tag::InvalidNameError => entry("invalid_tag", :unprocessable_content, :tags),

    # Tasks
    Tasks::NotATaskError => entry("not_a_task", :unprocessable_content),
    Tasks::AlreadyClaimedError => entry("already_claimed", :conflict),
    Tasks::NoPendingTaskError => entry("no_pending_task", :not_found),
    Tasks::WrongClaimerError => entry("wrong_claimer", :conflict),
    Tasks::ReasonRequiredError => entry("reason_required", :unprocessable_content, :reason),
    Tasks::InvalidStatusError => entry("invalid_status", :unprocessable_content, :status),
    Tasks::InvalidLeaseError => entry("invalid_lease", :unprocessable_content, :lease_seconds),
    Tasks::InvalidArgumentError => entry("invalid_argument", :unprocessable_content),
    Tasks::InvalidNoteError => entry("note_too_long", :unprocessable_content),

    # Checkpoints and identity
    Checkpoints::EmptyContentError => entry("empty_content", :unprocessable_content, :content),
    Checkpoints::NoAgentError => entry("no_agent", :unprocessable_content),
    Checkpoint::NoHandleError => entry("no_handle", :unprocessable_content),
    Actor::InvalidAgentError => entry("invalid_agent", :unprocessable_content, :agent),

    # Events
    Events::InvalidTimestampError => entry("invalid_timestamp", :unprocessable_content),
    Events::InvalidCursorError => entry("invalid_cursor", :unprocessable_content),

    # Tokens
    Tokens::Revoke::ForbiddenError => entry("forbidden", :forbidden),
    Tokens::Revoke::AlreadyRevokedError => entry("already_revoked", :conflict)
  }.freeze

  def self.classes
    ENTRIES.keys
  end

  # The entry for an error or its nearest registered ancestor, or nil.
  def self.for(error)
    error.class.ancestors.each do |klass|
      entry = ENTRIES[klass]
      return entry if entry
    end
    nil
  end

  # What every transport shows. Rails' own wording for these two names tables
  # and columns, so they say what was invalid or missing instead.
  def self.message(error)
    case error
    when ActiveRecord::RecordInvalid then error.record.errors.full_messages.join(", ")
    when ActiveRecord::RecordNotFound then error.model&.underscore&.humanize&.downcase || "record"
    else error.message
    end
  end
end
