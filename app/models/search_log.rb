class SearchLog < ApplicationRecord
  belongs_to :token, optional: true

  validates :query, presence: true
end
