module Versions
  # One prior version of a live asset, by id.
  class Read
    def self.query(slug:, id:, actor: nil)
      List.query(slug:, actor:).find_by(id:) or raise NotFoundError, "version #{id} is not on #{slug}"
    end
  end
end
