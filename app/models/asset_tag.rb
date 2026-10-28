class AssetTag < ApplicationRecord
  belongs_to :asset
  belongs_to :tag
end
