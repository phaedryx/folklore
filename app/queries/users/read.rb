module Users
  # One user by handle; an unknown handle raises ActiveRecord::RecordNotFound.
  class Read
    def self.query(handle:)
      User.find_by!(handle: handle.to_s)
    end
  end
end
