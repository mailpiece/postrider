class Access < ApplicationRecord
  belongs_to :account, default: -> { user.account }
  belongs_to :domain
  belongs_to :user
end
