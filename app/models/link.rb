class Link < ApplicationRecord
  belongs_to :src_asset, class_name: "Asset"
  belongs_to :dst_asset, class_name: "Asset", optional: true

  KINDS = %w[wikilink].freeze

  validates :dst_ref, presence: true
  validates :kind, inclusion: { in: KINDS }
end
