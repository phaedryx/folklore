class Version < ApplicationRecord
  belongs_to :asset
  belongs_to :actor_user, class_name: "User", optional: true
  belongs_to :actor_token, class_name: "Token", optional: true
end
