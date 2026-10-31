module FolkloreMcp
  module Tools
    # Tools over the asset domain. Each tool raises the domain's errors and the
    # base class renders them (see DomainErrors).
    module Assets
      # Fields a tool may return about one asset; every one optional because
      # `read` returns only what was asked for.
      ASSET_FIELDS = proc do
        optional(:slug).filled(:string)
        optional(:name).filled(:string)
        optional(:content).maybe(:string)
        optional(:content_type).maybe(:string)
        optional(:kind).filled(:string)
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
    end
  end
end
