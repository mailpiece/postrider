class Pause < ApplicationRecord
  belongs_to :delivery, optional: true

  normalizes :recipient_domain, :provider, with: ->(name) { name.to_s.strip.downcase }

  validates :recipient_domain, :provider, presence: true

  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  def resume
    transaction do
      destroy!
      delivery&.track_recipient_domain_event "resumed", provider: provider
    end
  end

  def provider_label
    MailProvider.label(provider)
  end
end
