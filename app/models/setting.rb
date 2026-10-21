class Setting < ApplicationRecord
  belongs_to :account, default: -> { Current.account }

  normalizes :bounce_address, with: ->(value) { value.to_s.strip.presence }
end
