class Mailbox < ApplicationRecord
  include ForwardConfirmable, Suspending

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  normalizes :local_part, with: ->(v) { v.to_s.strip.downcase }
  normalizes :forward_to, with: ->(v) { v.to_s.strip.downcase.presence }

  validates :local_part, presence: true, uniqueness: { scope: :domain_id },
    format: { with: /\A[a-z0-9.!#$%&'*+\/=?^_`{|}~-]+\z/, message: "is not a valid mailbox" }
  validates :forward_to, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate :forward_to_is_elsewhere

  before_destroy :protect_reserved

  scope :ordered, -> { order(:local_part) }
  scope :forwarding, -> { where.not(forward_to: nil).where.not(forward_confirmed_at: nil) }

  # RFC 5321 postmaster + dmarc-reports; seeded with the domain, destroyed only with it.
  def reserved?
    local_part.in?(Domain::RESERVED_LOCAL_PARTS)
  end

  def forwarding?
    forward_to.present? && forward_confirmed_at.present?
  end

  def address
    "#{local_part}@#{domain.name}"
  end

  private
    def protect_reserved
      if reserved?
        errors.add(:base, "#{local_part} is required for this domain and can't be removed")
        throw :abort
      end
    end

    # A mailbox forwarding to itself is a loop we'd only catch once the mail is already circling.
    def forward_to_is_elsewhere
      if forward_to.present? && domain && forward_to == address
        errors.add(:forward_to, "can't be this mailbox")
      end
    end
end
