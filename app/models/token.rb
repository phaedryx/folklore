# An opaque bearer token. The plaintext ("flk_...") is shown once at issue
# time; only its SHA-256 digest is stored. Each token names the agent that
# holds it, which becomes the default actor identity for its writes.
class Token < ApplicationRecord
  belongs_to :user

  PREFIX = "flk_".freeze

  validates :agent_name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(plaintext)
    Digest::SHA256.hexdigest(plaintext)
  end

  def revoked?
    revoked_at.present?
  end
end
