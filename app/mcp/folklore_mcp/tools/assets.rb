module FolkloreMcp
  module Tools
    # Tools over the asset domain. The domain's errors are registered here
    # once, so each tool raises and the base class renders.
    module Assets
      FolkloreMcp::Tool.user_error(::Assets::NotFoundError, "Not found")
      FolkloreMcp::Tool.user_error(::Assets::ForbiddenError, "Forbidden")
      FolkloreMcp::Tool.user_error(::Assets::NameTakenError, "Conflict")
      FolkloreMcp::Tool.user_error(::Assets::ConflictError, "Conflict")
      FolkloreMcp::Tool.user_error(::Assets::AlreadyDeletedError, "Conflict")
      FolkloreMcp::Tool.user_error(::Assets::NotDeletedError, "Conflict")
      FolkloreMcp::Tool.user_error(::Assets::NotANoteError, "Invalid")
      FolkloreMcp::Tool.user_error(::Assets::InvalidStatusError, "Invalid")
      FolkloreMcp::Tool.user_error(::Assets::InvalidLocationError, "Invalid")
      FolkloreMcp::Tool.user_error(::Versions::NotFoundError, "Not found")
      FolkloreMcp::Tool.user_error(::Asset::ContentTooLargeError, "Invalid")

      # Fields a tool may return about one asset; every one optional because
      # `read` returns only what was asked for.
      ASSET_FIELDS = proc do
        optional(:slug).filled(:string)
        optional(:name).filled(:string)
        optional(:content).maybe(:string)
        optional(:content_type).maybe(:string)
        optional(:status).maybe(:string)
        optional(:owner_handle).filled(:string)
        optional(:owner).filled(:string)
        optional(:path).filled(:string)
        optional(:dir).filled(:string)
        optional(:location).filled(:string)
        optional(:tags).array(:string)
        optional(:created_at).filled(:string)
        optional(:updated_at).filled(:string)
        optional(:version).filled(:integer)
        optional(:stale_after).maybe(:string)
        optional(:verified_at).maybe(:string)
        optional(:created_by).maybe(:hash) { required(:handle).filled(:string); required(:agent).filled(:string) }
        optional(:updated_by).maybe(:hash) { required(:handle).filled(:string); required(:agent).filled(:string) }
        optional(:verified_by).maybe(:hash) { required(:handle).filled(:string); required(:agent).filled(:string) }
        optional(:backlinks).array(:hash) do
          required(:slug).filled(:string)
          required(:location).filled(:string)
          required(:name).filled(:string)
        end
        optional(:task).maybe(:hash) do
          required(:status).filled(:string)
          optional(:claimed_by).maybe(:string)
          optional(:lease_until).maybe(:string)
        end
      end

      ASSET_SCHEMA = Dry::Schema.JSON(&ASSET_FIELDS)

      # The read tools answer with the asset's content or chosen fields.
      READ_FIELDS = %i[content name path content_type status owner tags created_at updated_at
                       backlinks created_by updated_by verified_by version].freeze
    end
  end
end
