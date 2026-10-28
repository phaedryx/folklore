# An opaque bearer token. The plaintext ("flk_...") is shown once at issue
# time; only its SHA-256 digest is stored. Each token names the agent that
# holds it, which becomes the default actor identity for its writes.
class Token < ApplicationRecord
  belongs_to :user

  PREFIX = "flk_".freeze
  SCOPES = %w[read write].freeze

  validates :agent_name, presence: true,
                         format: { with: Actor::AGENT_REGEX, message: "must be a lowercase slug" },
                         exclusion: { in: [ Actor::WEB_AGENT ], message: "is reserved" }
  validates :token_digest, presence: true, uniqueness: true
  validates :scopes, presence: true
  validate :scopes_are_known

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(plaintext)
    Digest::SHA256.hexdigest(plaintext)
  end

  def revoked?
    revoked_at.present?
  end

  # Read-only tools and GET API calls need the read scope.
  def readable?
    scopes.include?("read")
  end

  # Write tools and non-GET API calls need the write scope.
  def writable?
    scopes.include?("write")
  end

  private

  def scopes_are_known
    unknown = Array(scopes) - SCOPES
    errors.add(:scopes, "contain unknown #{unknown.join(', ')}") if unknown.any?
  end
end
