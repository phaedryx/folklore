module Users
  # Creates a user, or returns the one already registered under the email.
  # Email normalization lives here, not in a model callback.
  class Provision
    def self.mutate(handle:, email:, name:, password: nil)
      new(handle:, email:, name:, password:).mutate
    end

    def initialize(handle:, email:, name:, password: nil)
      @handle = handle.to_s.strip
      @email = email.to_s.downcase.strip
      @name = name.to_s.strip
      @password = password
    end

    def mutate
      existing = User.find_by("lower(email) = ?", @email)
      if existing
        existing.update!(password: @password) if existing.password_digest.blank? && @password.present?
        return existing
      end

      user = User.new(handle: @handle, email: @email, name: @name.presence || @email.split("@").first)
      user.password = @password if @password.present?
      user.save!
      user
    end
  end
end
