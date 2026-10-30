class Tag < ApplicationRecord
  has_many :asset_tags
  has_many :assets, through: :asset_tags

  InvalidNameError = Class.new(StandardError)

  # Mirrors the CHECK constraint on tags.name.
  MAX_NAME_LENGTH = 100

  validates :name, presence: true, uniqueness: true

  def self.normalize(name)
    name.to_s.downcase.strip
  end

  # Takes a normalized name.
  def self.validate_name!(name)
    raise InvalidNameError, "tag is required" if name.empty?
    return if name.length <= MAX_NAME_LENGTH

    raise InvalidNameError, "tag is #{name.length} characters, over the #{MAX_NAME_LENGTH} character limit"
  end

  # Attaches the named tags to an asset, creating any that do not exist.
  # Blank and duplicate names are dropped.
  def self.attach(asset, names)
    # Sorted, so two writers inserting the same new tags lock them in one order.
    names.map { |n| normalize(n) }.reject(&:empty?).uniq.sort.each do |name|
      validate_name!(name)
      AssetTag.find_or_create_by!(asset:, tag: find_or_insert!(name))
    end
  end

  # The tag with this (normalized) name, inserted if no one has used it yet.
  # Two first uses race to insert; the unique index decides and the loser's
  # insert does nothing, so neither sees an error. find_or_create_by! is not
  # enough: its uniqueness validation can see the winner's row commit after
  # its lookup missed, and raises "Name has already been taken".
  def self.find_or_insert!(name)
    insert({ name: }, unique_by: :name)
    find_by!(name:)
  end
end
