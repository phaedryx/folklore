class Tag < ApplicationRecord
  has_many :asset_tags
  has_many :assets, through: :asset_tags

  validates :name, presence: true, uniqueness: true

  def self.normalize(name)
    name.to_s.downcase.strip
  end

  # Attaches the named tags to an asset, creating any that do not exist.
  # Blank and duplicate names are dropped.
  def self.attach(asset, names)
    names.map { |n| normalize(n) }.reject(&:empty?).uniq.each do |name|
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
