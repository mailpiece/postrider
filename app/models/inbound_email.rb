class InboundEmail < ApplicationRecord
  include Eventable, Sourced, Incineratable, Postable, Forwarding

  class Abandoned < StandardError; end

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  enum :status, %w[ pending processing delivered failed bounced held ].index_by(&:itself), default: :pending

  scope :in_flight, -> { where(status: %w[ pending processing ]) }
  scope :processed, -> { where(status: %w[ delivered failed bounced ]) }

  # Held mail uses a longer clock than processed retention, then ages out regardless.
  scope :due_for_incineration, -> {
    processed
      .where("COALESCE(inbound_emails.forwarded_at, inbound_emails.created_at) < ?", Relay.retention_period.ago)
      .or(held.where(created_at: ...Relay.held_retention_period.ago))
      .incineratable
  }

  def self.fail_abandoned
    pending.or(processing).where("created_at < ?", 1.day.ago).find_each do |inbound_email|
      stuck_status = inbound_email.status
      inbound_email.fail_permanently(reason: "abandoned")
      Rails.error.report Abandoned.new("InboundEmail #{inbound_email.id} was still #{stuck_status} after a day"), severity: :error
    end
  end

  def processed?
    delivered? || failed? || bounced?
  end

  def to_bounce_address?
    rcpt_to == account.setting.bounce_address
  end

  def to_dmarc_reports_address?
    domain && rcpt_to.to_s.casecmp?("dmarc-reports@#{domain.name}")
  end

  def dmarc_report
    @dmarc_report ||= DmarcReport.for(self)
  end

  def forward_later(ip:, helo:)
    ForwardJob.perform_later(self, ip:, helo:)
  end

  # Authentication and attachments come before the transaction: a slow zone would
  # hold the write lock, and Active Storage uploads on commit.
  def forward(ip:, helo:)
    processing!
    authenticate(ip:, helo:)
    extract_attachments

    transaction do
      track_event to_bounce_address? ? "bounce_received" : "received", **received_particulars(ip)

      if forwarding_applies?
        forward_or_hold
      else
        update! status: :delivered, forwarded_at: Time.current
      end
    end
  end

  def discard(reason: "unregistered_recipient")
    transaction do
      update! status: :bounced, forwarded_at: Time.current
      track_event "discarded", rcpt_to: rcpt_to, reason: reason
    end
  end

  def fail_permanently(reason:)
    transaction do
      failed!
      track_event "failed", rcpt_to: rcpt_to, reason: reason
    end
  end

  def correlate_bounce_later
    BounceCorrelationJob.perform_later(self)
  end

  def correlate_bounce
    if delivery = Delivery::ReturnPath.find_delivery(rcpt_to)
      transaction do
        delivery.record_async_bounce(dsn_raw: raw)
        update! status: :delivered, forwarded_at: Time.current
      end
    else
      discard(reason: "uncorrelated_bounce")
    end
  end

  def webhook_payload(action)
    Payload.new(self).to_h
  end

  def relayable_raw
    RelayHeaders.new(self).prepended_to(raw)
  end

  def parsed_email
    @parsed_email ||= ParsedEmail.new(raw)
  end

  private
    def authenticate(ip:, helo:)
      update!(**InboundAuthentication.verdicts(raw, ip:, helo:, mail_from:))
    end

    # The host is named only once its name resolved back to the address.
    def received_particulars(ip)
      { rcpt_to: rcpt_to, remote_ip: ip, remote_host: remote_host }.compact
    end
end
