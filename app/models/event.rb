class Event < ApplicationRecord
  NOTABLE_ACTIONS = %w[ delivery_failed delivery_bounced delivery_withheld inbound_email_bounce_received inbound_email_failed
    inbound_email_discarded webhook_deactivated domain_verified domain_verification_lost
    recipient_domain_paused recipient_domain_resumed sending_token_refused ].freeze

  BOUNCE_ACTIONS = %w[ delivery_bounced inbound_email_bounce_received ].freeze

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain
  belongs_to :eventable, polymorphic: true

  has_many :webhook_deliveries, class_name: "Webhook::Delivery", dependent: :delete_all

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :notable, -> { where(action: NOTABLE_ACTIONS) }
  scope :bounced, -> { where(action: BOUNCE_ACTIONS) }
  scope :preloaded, -> { includes(eventable: :mailpiece) }

  after_create_commit :dispatch_webhooks_later

  def self.purge(purgeable)
    Webhook::Delivery.where(event_id: purgeable.select(:id)).delete_all
    purgeable.delete_all
  end

  def action
    super.inquiry
  end

  def description
    description_for(nil)
  end

  def description_for(user)
    Event::Description.new(self, user).to_s
  end

  # The phrase a message was withheld for is the admins' to know.
  def particulars_for(user)
    if user&.admin?
      particulars
    else
      particulars.except("phrase")
    end
  end

  def body
    { event: action, payload: webhook_payload }.to_json
  end

  private
    # A sending token may be gone by the time its event is sent, so the event carries it.
    def webhook_payload
      if action.start_with?("sending_token_")
        eventable.webhook_payload(action).merge(particulars.symbolize_keys)
      else
        eventable.webhook_payload(action)
      end
    end

    def dispatch_webhooks_later
      Event::WebhookDispatchJob.perform_later(self)
    end
end
