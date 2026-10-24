require "mail"

class Message < ApplicationRecord
  include Eventable, Sourced, Submitting, Composing, Incineratable

  # How the message came to exist, which decides whether this domain's rules apply
  # to it. Never inferred from tags: those are the sender's to write.
  # System mail is the relay's own, sent from the domain and kept out of the tenant's sight.
  enum :origin, %w[ submitted forwarded system ].index_by(&:itself), default: :submitted

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  has_many :deliveries, dependent: :delete_all do
    def create_for(recipients)
      Array(recipients).map { |rcpt_to| create!(rcpt_to: rcpt_to) }
    end
  end

  serialize :tags, type: Array, coder: JSON
  serialize :metadata, coder: JSON

  validates :mail_from, presence: true
  validates :raw, presence: true, unless: :incinerated?
  validate :raw_within_max_message_size
  validate :domain_verified_for_sending, on: :create, unless: :forwarded?
  validate :domain_sending, on: :create, unless: :forwarded?

  normalizes :tags, with: ->(value) { Array.wrap(value).map(&:to_s).map(&:strip).reject(&:blank?).uniq }
  normalizes :metadata, with: ->(value) {
    value.is_a?(Hash) ? value.to_h { |key, entry| [ key.to_s, entry.to_s ] }.reject { |key, _| key.blank? } : {}
  }

  before_destroy :purge_delivery_mailpieces, prepend: true

  after_create_commit :extract_attachments_later

  scope :due_for_incineration, -> {
    where(created_at: ...Relay.retention_period.ago)
      .incineratable
      .where.not(id: Delivery.in_flight.select(:message_id))
  }

  def smtp_envelope_from
    envelope_from.nil? ? mail_from : envelope_from
  end

  # A forward's From: is a third party's, and it already carries the relay's ARC seal;
  # signing it here would have this domain vouch for mail it didn't write.
  def signable?
    !forwarded?
  end

  def parsed_email
    @parsed_email ||= ParsedEmail.new(raw)
  end

  def extract_attachments_later
    ExtractionJob.perform_later(self)
  end

  private
    def assign_source(source)
      super
      self.mail_message_id = source.message_id
    end

    def should_track_event?
      !system?
    end

    def purge_delivery_mailpieces
      Delivery.purge_mailpieces(deliveries)
    end

    def raw_within_max_message_size
      errors.add(:raw, "is too large") if raw.present? && raw.bytesize > Relay.max_outbound_message_size
    end

    # Only mail this domain originates: a forward travels under the relay's seal,
    # so it neither needs nor uses the tenant's published key.
    def domain_verified_for_sending
      if domain && !domain.verified?
        errors.add(:domain, "isn't verified for sending — publish its DKIM record, then check DNS")
      end
    end

    def domain_sending
      if domain && !domain.sending?
        errors.add(:domain, "isn't sending: turned off in its settings")
      end
    end
end
