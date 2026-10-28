require "marcel"

class Asset < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :created_by_token, class_name: "Token", optional: true
  belongs_to :updated_by_token, class_name: "Token", optional: true
  belongs_to :verified_by_token, class_name: "Token", optional: true
  has_one :task
  has_many :asset_tags
  has_many :tags, through: :asset_tags
  has_many :versions
  has_many :links, foreign_key: :src_asset_id, inverse_of: :src_asset
  has_many :inbound_links, class_name: "Link", foreign_key: :dst_asset_id, inverse_of: :dst_asset
  has_many :events

  scope :live,       -> { where(deleted_at: nil) }
  scope :tombstoned, -> { where.not(deleted_at: nil) }
  # Staleness is opt-in: an asset with no review date has made no promise to be
  # re-verified, so it is never stale.
  scope :stale,      -> { where(stale_after: ...Date.current) }
  scope :not_stale,  -> { where(stale_after: nil).or(where(stale_after: Date.current..)) }
  # Assets in the given directory or any directory below it.
  scope :under_dir, ->(prefix) {
    where(dir: prefix).or(where("assets.dir LIKE ?", "#{sanitize_sql_like(prefix)}/%"))
  }

  # The row lock a write takes. Writers never change an asset's key, so they
  # take FOR NO KEY UPDATE rather than FOR UPDATE: it still serialises writers
  # of one asset, but does not block the key-share lock a foreign key check
  # takes, so two assets written at once to link to each other cannot deadlock.
  WRITE_LOCK = "FOR NO KEY UPDATE".freeze

  SLUG_CHARS = "0123456789abcdefghjkmnpqrstvwxyz".freeze
  NOTE_STATUSES = %w[open done].freeze
  # Second path segments the app owns: `<handle>/archive` is the web archive
  # page, `<handle>/state/<agent>` holds checkpoints.
  RESERVED_SEGMENTS = %w[archive state].freeze
  # Directory segments appear in URLs and on disk when exported, so they are
  # limited to characters that need no escaping anywhere.
  DIR_SEGMENT_REGEX = /\A[A-Za-z0-9._-]+\z/
  KNOWN_FILE_EXTENSIONS = %w[
    md markdown txt rb py js ts jsx tsx json yml yaml toml
    html erb css scss sh fish xml csv log conf ini lock
  ].freeze

  InvalidNameError = Class.new(StandardError)
  InvalidDirError = Class.new(StandardError)
  ReservedDirError = Class.new(InvalidDirError)
  InvalidStaleAfterError = Class.new(StandardError)
  ContentTooLargeError = Class.new(StandardError)

  # Mirrors the CHECK constraint on assets.content, so a caller gets a readable
  # error instead of a statement failure.
  MAX_CONTENT_BYTES = 1_048_576

  validates :slug, :dir, :name, presence: true
  validates :status, inclusion: { in: NOTE_STATUSES }, allow_nil: true

  def self.generate_slug
    loop do
      bits = SecureRandom.random_bytes(5).bytes.map { |b| b.to_s(2).rjust(8, "0") }.join
      slug = 8.times.map { |i| SLUG_CHARS[bits[i * 5, 5].to_i(2)] }.join
      return slug unless exists?(slug:)
    end
  end

  # Narrows to assets carrying every named tag (AND semantics). Returns none
  # if any named tag does not exist. Names are case/whitespace-normalized.
  def self.tagged_with(*names)
    scope = all
    names.flatten.map { |n| n.to_s.downcase.strip }.reject(&:empty?).each do |name|
      tag = Tag.find_by(name:)
      return none unless tag
      scope = scope.where(id: AssetTag.where(tag_id: tag.id).select(:asset_id))
    end
    scope
  end

  def self.validate_content!(content)
    return if content.nil? || content.bytesize <= MAX_CONTENT_BYTES

    raise ContentTooLargeError, "content is #{content.bytesize} bytes, over the 1 MiB cap"
  end

  def self.sha256(content)
    content.nil? ? nil : Digest::SHA256.hexdigest(content)
  end

  # The MIME type a name implies, with text/plain for anything unrecognised.
  def self.infer_content_type(name)
    detected = Marcel::MimeType.for("", name:)
    detected == "application/octet-stream" ? "text/plain" : detected
  end

  def self.validate_name!(name)
    raise InvalidNameError, "name is required" if name.to_s.empty?
    raise InvalidNameError, "name cannot contain '/'" if name.include?("/")
    raise InvalidNameError, "name cannot contain whitespace" if name.match?(/\s/)
    raise InvalidNameError, "name cannot be '.' or '..'" if name == "." || name == ".."
  end

  # A dir is "<handle>" or "<handle>/<segment>/...". Reserved second segments
  # are refused unless the caller owns them (checkpoints pass allow_reserved).
  def self.validate_dir!(dir, allow_reserved: false)
    raise InvalidDirError, "path is required" if dir.to_s.empty?
    raise InvalidDirError, "path cannot start or end with '/'" if dir.start_with?("/") || dir.end_with?("/")

    segments = dir.split("/")
    raise InvalidDirError, "path cannot contain empty segments" if segments.any?(&:empty?)
    if segments.any? { |s| s == "." || s == ".." }
      raise InvalidDirError, "path segments cannot be '.' or '..'"
    end
    unless segments.first.match?(User::HANDLE_REGEX)
      raise InvalidDirError, "path must start with a workspace handle, got #{segments.first.inspect}"
    end
    segments.each do |segment|
      next if segment.match?(DIR_SEGMENT_REGEX)
      raise InvalidDirError, "path segment #{segment.inspect} may only contain letters, digits, '.', '_' and '-'"
    end

    last = segments.last
    if last.match?(/\.(#{KNOWN_FILE_EXTENSIONS.join('|')})\z/i)
      raise InvalidDirError, "path segment #{last.inspect} looks like a filename; put it in 'name' instead"
    end

    if !allow_reserved && RESERVED_SEGMENTS.include?(segments[1])
      raise ReservedDirError, "#{segments.first(2).join('/')} is reserved"
    end
  end

  # Normalizes a caller-supplied review date. Blank clears it (nil); anything
  # unparseable is an error rather than a silently-dropped filter.
  def self.parse_stale_after!(value)
    return nil if value.nil?
    return value if value.is_a?(Date)

    text = value.to_s.strip
    return nil if text.empty?

    Date.iso8601(text)
  rescue ArgumentError
    raise InvalidStaleAfterError, "stale_after must be an ISO date (YYYY-MM-DD), got #{value.inspect}"
  end

  def location
    "#{dir}/#{name}"
  end

  def workspace_handle
    dir.split("/").first
  end

  def task?
    task.present?
  end

  def stale?
    stale_after.present? && stale_after < Date.current
  end
end
