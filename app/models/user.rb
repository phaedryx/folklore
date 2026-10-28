class User < ApplicationRecord
  has_many :tokens, dependent: :destroy
  has_many :assets, foreign_key: :owner_id, inverse_of: :owner, dependent: :restrict_with_exception

  has_secure_password validations: false

  HANDLE_REGEX = /\A[a-z](?:[a-z0-9]|-(?=[a-z0-9])){1,31}\z/
  EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\z/

  RESERVED_HANDLES = %w[mcp api auth assets rails settings sign_in sign_out].freeze

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
