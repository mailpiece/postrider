class Delivery < ApplicationRecord
  include Eventable, Delivering, Bouncing, Pausable, Pacing, Postable

  belongs_to :account, default: -> { message.account }
  belongs_to :domain, default: -> { message.domain }
  belongs_to :message
  has_many :attempts, -> { order(:created_at) }, class_name: "Delivery::Attempt", dependent: :delete_all

  before_create :inherit_message_details

  enum :status, %w[ queued delivered deferred bounced exhausted suppressed withheld ].index_by(&:itself), default: :queued

  scope :in_flight, -> { where(status: %w[ queued deferred ]) }
  scope :failed, -> { where(status: %w[ bounced exhausted suppressed ]) }

  delegate :parsed_email, :raw_email, :raw, :attachments, to: :message

  def last_attempt
    attempts.order(:created_at).last
  end

  # Events + SMTP attempts as one timeline.
  def activity_log
    (events.ordered.to_a + attempts.to_a).sort_by(&:created_at).reverse
  end

  private
    def inherit_message_details
      self.subject = message.subject
      self.mail_from = message.mail_from
    end

    # The relay's own mail carries secrets the tenant must not read: no mail log row, no events, no webhooks.
    def should_establish_mailpiece?
      !message.system?
    end

    def should_track_event?
      !message.system?
    end
end
