class Webhook < ApplicationRecord
  include Triggerable, Eventable

  ACTION_MAILBOX_RELAY_URL_REGEX = %r{/rails/action_mailbox/relay/inbound_emails\z}i
  SLACK_WEBHOOK_URL_REGEX = %r{//hooks\.slack\.com/services/T[^/]+/B[^/]+/[^/]+\z}i

  PERMITTED_SCHEMES = (Rails.env.local? ? %w[ http https ] : %w[ https ]).freeze
  PERMITTED_ACTIONS = %w[
    inbound_email_received
    inbound_email_bounce_received
    inbound_email_forwarded
    delivery_delivered
    delivery_deferred
    delivery_failed
    delivery_bounced
    recipient_domain_paused
    recipient_domain_resumed
    sending_token_created
    sending_token_revoked
    sending_token_refused
  ].freeze
  ACTION_MAILBOX_RELAY_PERMITTED_ACTIONS = %w[ inbound_email_received inbound_email_bounce_received ].freeze

  has_secure_token :signing_secret
  encrypts :signing_secret

  has_many :deliveries, class_name: "Webhook::Delivery", dependent: :delete_all
  has_one :delinquency_tracker, class_name: "Webhook::DelinquencyTracker", dependent: :delete

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  serialize :subscribed_actions, type: Array, coder: JSON

  scope :ordered, -> { order(name: :asc, id: :desc) }
  scope :active, -> { where(active: true) }

  after_create :create_delinquency_tracker!

  normalizes :subscribed_actions, with: ->(value) { Array.wrap(value).map(&:to_s).uniq & PERMITTED_ACTIONS }
  normalizes :url, with: ->(url) { url.to_s.strip }
  normalizes :signing_secret, with: ->(secret) { secret.strip }

  validates :name, presence: true
  validates :signing_secret, length: { minimum: 16 }
  validate :validate_url
  validate :validate_subscribed_actions_for_action_mailbox_relay

  # Like a password, a blank secret keeps the current one, or lets one be generated.
  def signing_secret=(secret)
    super if secret.present?
  end

  def activate
    update! active: true unless active?
  end

  def deactivate
    update! active: false
  end

  def for_action_mailbox_relay?
    url.match? ACTION_MAILBOX_RELAY_URL_REGEX
  end

  def for_slack?
    url.match? SLACK_WEBHOOK_URL_REGEX
  end

  # A relay expects raw mail, so a test envelope would only ever earn a 415.
  def testable?
    active? && !for_action_mailbox_relay?
  end

  def test
    trigger track_event("tested", sent_at: Time.current, sent_by: Current.user.name)
  end

  def webhook_payload(action)
    { webhook_id: id, domain_id: domain_id, domain: domain.name, name: name, url: url }
  end

  private
    def validate_url
      uri = URI.parse(url.presence)

      if PERMITTED_SCHEMES.exclude?(uri.scheme)
        errors.add :url, "must use #{PERMITTED_SCHEMES.join(" or ")}"
      end
    rescue URI::InvalidURIError
      errors.add :url, "is not a valid URL"
    end

    def validate_subscribed_actions_for_action_mailbox_relay
      if for_action_mailbox_relay? && (subscribed_actions - ACTION_MAILBOX_RELAY_PERMITTED_ACTIONS).any?
        errors.add :subscribed_actions, "can only include inbound_email_received and inbound_email_bounce_received when the URL points at an Action Mailbox relay ingress"
      end
    end
end
