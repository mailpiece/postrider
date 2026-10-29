class Suppression < ApplicationRecord
  belongs_to :account, default: -> { domain.account }
  belongs_to :domain, counter_cache: true

  def self.normalize_address(address)
    address.to_s.strip.downcase
  end

  normalizes :address, with: ->(address) { normalize_address(address) }

  validates :address, presence: true, uniqueness: { scope: :domain_id }

  scope :ordered, -> { order(created_at: :desc) }
end
