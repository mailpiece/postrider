class Pause < ApplicationRecord
  belongs_to :delivery, optional: true

  normalizes :recipient_domain, with: ->(name) { name.to_s.strip.downcase }

  validates :recipient_domain, presence: true

  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  def resume
    transaction do
      destroy!
      delivery&.track_recipient_domain_event "resumed"
    end
  end
end
