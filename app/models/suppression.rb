class Suppression < ApplicationRecord
  LIFETIME = 30.days

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain, counter_cache: true

  def self.normalize_address(address)
    address.to_s.strip.downcase
  end

  normalizes :address, with: ->(address) { normalize_address(address) }

  validates :address, presence: true, uniqueness: { scope: :domain_id }

  scope :ordered, -> { order(created_at: :desc) }

  # Expired rows remain for history; active excludes them.
  scope :active, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }

  def expired?
    expires_at&.past? || false
  end
end
