class User < ApplicationRecord
  # No association cleanup options anywhere: they are destroy callbacks in
  # disguise, and the database foreign keys already refuse to orphan rows.
  has_many :tokens
  has_many :assets, foreign_key: :owner_id, inverse_of: :owner

  has_secure_password validations: false

  HANDLE_REGEX = /\A[a-z](?:[a-z0-9]|-(?=[a-z0-9])){1,31}\z/
  EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\z/

  RESERVED_HANDLES = %w[mcp api auth assets rails settings sign_in sign_out].freeze

  # A bcrypt hash of a random string, compared against when no user (or no
  # password) matches, so an unknown email costs the same as a wrong password.
  DUMMY_PASSWORD_DIGEST = BCrypt::Password.create(SecureRandom.hex(16), cost: BCrypt::Engine.cost).freeze

  validates :email, presence: true,
                    format: { with: EMAIL_REGEX },
                    uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :handle,
            allow_nil: true,
            uniqueness: true,
            format: { with: HANDLE_REGEX, message: "is not a valid handle" },
            exclusion: { in: RESERVED_HANDLES, message: "is reserved" }

  validate :email_unchanged, on: :update
  validate :handle_unchanged_once_set, on: :update

  # Password sign-in: case-insensitive on email, constant-time on failure.
  def self.authenticate_by_email(email, password)
    user = find_by("lower(email) = ?", email.to_s.downcase.strip)
    if user&.password_digest.present?
      user.authenticate(password.to_s) || nil
    else
      BCrypt::Password.new(DUMMY_PASSWORD_DIGEST).is_password?(password.to_s)
      nil
    end
  end

  # Writes to a workspace belong to the user whose handle heads its path.
  def can_write_to_workspace?(handle)
    handle == self.handle
  end

  private

  def email_unchanged
    errors.add(:email, "is immutable") if email_changed?
  end

  def handle_unchanged_once_set
    if handle_was.present? && handle != handle_was
      errors.add(:handle, "is immutable once set")
    end
  end
end
