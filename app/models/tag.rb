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
      AssetTag.find_or_create_by!(asset:, tag: find_or_create_by!(name:))
    end
  end
end
