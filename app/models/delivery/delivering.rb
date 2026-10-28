module Delivery::Delivering
  extend ActiveSupport::Concern

  PERMANENT_CATEGORIES = %i[ invalid full oversized ].freeze

  SUPPRESSIBLE_CATEGORIES = %i[ invalid ].freeze

  RETRY_SCHEDULE = [ 15.minutes, 1.hour, 2.hours, 4.hours, 8.hours, 16.hours, 1.day ].freeze

  def deliver_later
    if paced?
      Delivery::PaceJob.perform_later(self)
    else
      Delivery::DeliverJob.perform_later(self)
    end
  end

  def deliver
    return if delivered? || bounced? || suppressed? || withheld? || exhausted?

    if recipient_suppressed?
      transaction do
        suppressed!
        track_event("failed", rcpt_to: rcpt_to, reason: "suppressed")
      end
    elsif held_by_pause?
      transaction do
        deferred!
        track_event("deferred", rcpt_to: rcpt_to, reason: "recipient_domain_paused")
      end

      raise "Deferred delivering to #{rcpt_to}: sending to #{recipient_domain} is paused"
    else
      # DKIM last: it hashes the body, so any rewrite above this line breaks the signature.
      result = deliver_over_smtp(outgoing_raw)

      transaction do
        attempts.create! code: result.code, output: result.output, mx_host: result.mx_host, transcript: result.transcript

        case result.status
        when :sent
          delivered!
          track_event("delivered", rcpt_to: rcpt_to)
        when :hard_fail
          record_rejection(result)
        when :session_fail
          exhaust
        when :soft_fail
          defer(result)
        else
          raise "Unknown delivery status #{result.status.inspect} for delivery #{id}"
        end
      end

      # Raising drives retry_on, and comes after the transaction so it keeps the deferral.
      if deferred?
        raise "Deferred delivering to #{rcpt_to}: #{result.output}"
      end
    end
  end

  def withhold(phrase)
    transaction do
      withheld!
      track_event("withheld", rcpt_to: rcpt_to, phrase: phrase)
    end
  end

  def exhaust
    transaction do
      exhausted!
      track_event("failed", rcpt_to: rcpt_to, reason: "exhausted")
    end
  end

  def smtp_envelope_from
    # A smarthost may refuse a null sender. ReturnPath never matches a system delivery, so its bounces are refused.
    if message.system? && relaying?
      Delivery::ReturnPath.new(self).address || message.smtp_envelope_from
    elsif !message.envelope_from.nil?
      message.smtp_envelope_from
    elsif return_path = Delivery::ReturnPath.new(self).address
      return_path
    else
      message.smtp_envelope_from
    end
  end

  def next_retry_at
    if deferred? && last_attempt && (relaying? || !provider_paused?(last_attempt.mx_host))
      last_attempt.created_at + RETRY_SCHEDULE[[ attempts.count - 1, RETRY_SCHEDULE.size - 1 ].min]
    end
  end

  private
    def recipient_suppressed?
      domain.suppressions.active.exists?(address: Suppression.normalize_address(rcpt_to))
    end

    def outgoing_raw
      if message.signable?
        Delivery::DkimSigning.sign(message.raw, domain: domain)
      else
        message.raw
      end
    end

    # Transient DNS is a soft fail like an unreachable MX — don't escape and silently defer.
    def deliver_over_smtp(raw)
      SmtpDelivery.new(raw: raw, mail_from: smtp_envelope_from, rcpt_to: rcpt_to,
        hosts: destination_hosts, policy: mta_sts_policy).deliver
    rescue DnsResolver::TransientError => error
      SmtpDelivery::Result.new(:soft_fail, nil, error.message, nil, nil)
    end

    def destination_hosts
      @destination_hosts ||= if relaying?
        []
      else
        DnsResolver.mail_exchangers(recipient_domain)
      end
    end

    def mta_sts_policy
      if Relay.mta_sts? && !relaying?
        MtaStsPolicy.lookup(recipient_domain).policy
      end
    end

    def relaying?
      Relay.outbound_relay.present?
    end

    def recipient_domain
      rcpt_to.split("@", 2).last
    end

    def record_rejection(result)
      rejection = MailBounce.classify(response: result.output, sending_ip: Relay.own_addresses)

      if rejection.category.in?(PERMANENT_CATEGORIES)
        bounced!
        suppress(reason: rejection.category) if rejection.category.in?(SUPPRESSIBLE_CATEGORIES) && !message.system?
        suspend_forwarding_destination
        track_event("bounced", rcpt_to: rcpt_to, smtp_code: result.code, smtp_output: result.output,
          category: rejection.category.to_s)
      else
        pause_mail_provider(result) if !relaying? && blocklisted_by_recipient?(rejection)
        defer(result)
      end
    end

    def suppress(reason:)
      domain.suppressions.find_or_create_by!(address: rcpt_to) do |suppression|
        suppression.reason = reason
        suppression.expires_at = Suppression::LIFETIME.from_now
      end
    end

    # Forwarded mail's rcpt_to is the destination; a permanent bounce means stop forwarding there.
    def suspend_forwarding_destination
      Mailbox.suspend_forwarding_to(domain, rcpt_to) if message.forwarded?
    end

    def defer(result)
      deferred!
      track_event("deferred", rcpt_to: rcpt_to, smtp_code: result.code, smtp_output: result.output)
    end
end
