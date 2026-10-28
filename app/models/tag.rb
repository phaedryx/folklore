class Tag < ApplicationRecord
  has_many :asset_tags
  has_many :assets, through: :asset_tags

  validates :name, presence: true, uniqueness: true
end
