class InboundEmail < ApplicationRecord
  include Eventable, Sourced, Incineratable, Postable, Forwarding, Scorable

  class Abandoned < StandardError; end

  belongs_to :account, default: -> { domain.account }
  belongs_to :domain

  enum :status, %w[ pending processing delivered failed bounced held ].index_by(&:itself), default: :pending

  scope :ordered, -> { order(created_at: :desc) }
  scope :in_flight, -> { where(status: %w[ pending processing ]) }
  scope :processed, -> { where(status: %w[ delivered failed bounced ]) }

  # Held mail uses a longer clock than processed retention, then ages out regardless.
  scope :due_for_incineration, -> {
    processed
      .where("COALESCE(inbound_emails.forwarded_at, inbound_emails.created_at) < ?", Relay.retention_period.ago)
      .or(held.where(created_at: ...Relay.held_retention_period.ago))
      .incineratable
  }

  def self.purge(inbound_emails)
    inbound_emails.in_batches do |batch|
      transaction do
        purge_attachments batch
        Incineration.where(incinerable: batch).delete_all
        purge_mailpieces batch
        batch.delete_all
      end
    end
  end

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
    bounce_address = account.setting.bounce_address
    bounce_address.present? && rcpt_to.to_s.casecmp?(bounce_address)
  end

  # A look-alike sender reads as punycode, as its contact does, so it reads apart from the one it imitates.
  def sender_address
    lookalike_sender? ? Contact.normalize_email(mail_from) : mail_from
  end

  def lookalike_sender?
    HomographicSpoofing.email_address_spoof?(Contact.scrubbed(mail_from.to_s))
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

  # Authentication, attachments and the score come before the transaction: a slow zone
  # or scorer would hold the write lock, and Active Storage uploads on commit.
  def forward_now(ip:, helo:)
    processing!
    authenticate(ip:, helo:)
    extract_attachments
    score

    transaction do
      track_event to_bounce_address? ? "bounce_received" : "received", **received_particulars(ip)

      if forwarding_applies?
        forward_or_hold
      else
        update! status: :delivered, forwarded_at: Time.current
      end
    end
  end

  # Mail that is never forwarded is scored in the background, so History still has a verdict.
  def discard(reason: "unregistered_recipient")
    transaction do
      update! status: :bounced, forwarded_at: Time.current
      track_event "discarded", rcpt_to: rcpt_to, reason: reason
    end

    score_later
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

  # The delivery whose bounce address this mail came to.
  def matched_delivery
    Delivery::ReturnPath.find_delivery(rcpt_to)
  end

  def correlate_bounce
    if delivery = matched_delivery
      transaction do
        delivery.record_async_bounce(dsn_raw: raw)
        update! status: :delivered, forwarded_at: Time.current
      end

      score_later
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

  # Mail received before we stored the value still has to state an authserv-id.
  def stated_authentication_results
    authentication_results.presence ||
      MailAuth::AuthenticationResults.new(spf: nil, dkim: nil, dmarc: nil, mta: Relay.hostname).to_s
  end

  def parsed_email
    @parsed_email ||= ParsedEmail.new(raw)
  end

  private
    # The MX authenticates before it answers; this is for mail that reached us without verdicts.
    def authenticate(ip:, helo:)
      if authentication_results.nil?
        update!(**InboundAuthentication.verdicts(raw, ip:, helo:, mail_from:))
      end
    end

    # The host is named only once its name resolved back to the address.
    def received_particulars(ip)
      { rcpt_to: rcpt_to, remote_ip: ip, remote_host: remote_host }.compact
    end
end
