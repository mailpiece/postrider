module Delivery::Bouncing
  extend ActiveSupport::Concern

  STORED_DSN_LIMIT = 64.kilobytes

  def record_async_bounce(dsn_raw:)
    return if already_bounced?

    recipient = MailBounce.parse(dsn_raw).for(rcpt_to)
    rejection = classify_recipient(recipient)

    transaction do
      track_event("bounced", rcpt_to: rcpt_to, source: "dsn", dsn: dsn_raw.byteslice(0, STORED_DSN_LIMIT),
        category: rejection&.category&.to_s)

      if recipient&.permanent_failure? && rejection.category.in?(Delivery::Delivering::SUPPRESSIBLE_CATEGORIES)
        domain.suppressions.find_or_create_by!(address: rcpt_to) do |suppression|
          suppression.reason = rejection.category.to_s
          suppression.expires_at = Suppression::LIFETIME.from_now
        end
        suspend_forwarding_destination
      end
    end
  end

  def webhook_payload(action)
    case action
    when "delivery_bounced"
      delivery_payload.merge(raw: stored_dsn || dsn, category: bounce_category)
    when "delivery_deferred", "delivery_failed"
      if reason = latest_particular(action, "reason")
        delivery_payload.merge(reason: reason)
      else
        delivery_payload
      end
    when "recipient_domain_paused", "recipient_domain_resumed"
      delivery_payload.merge(recipient_domain: recipient_domain, provider: latest_particular(action, "provider") || recipient_domain)
    else
      delivery_payload
    end
  end

  private
    def already_bounced?
      bounced_event.present?
    end

    def classify_recipient(recipient)
      if recipient
        MailBounce.classify(
          response: recipient.diagnostic_code || recipient.status.to_s,
          sending_ip: Relay.own_addresses
        )
      end
    end

    def delivery_payload
      {
        delivery_id: id,
        status: status,
        rcpt_to: rcpt_to,
        mail_from: message.mail_from,
        message_id: message.mail_message_id,
        tags: message.tags,
        metadata: message.metadata || {},
        smtp_code: last_attempt&.code,
        smtp_output: last_attempt&.output,
        mx_host: last_attempt&.mx_host
      }
    end

    def stored_dsn
      bounced_event&.particulars&.dig("dsn")
    end

    def bounce_category
      bounced_event&.particulars&.dig("category")
    end

    def bounced_event
      events.where(action: "delivery_bounced").order(:created_at).last
    end

    def latest_particular(action, key)
      events.where(action: action).order(:created_at).last&.particulars&.dig(key)
    end

    def dsn
      DsnReport.new(rcpt_to: rcpt_to, code: last_attempt.code, diagnostic: last_attempt.output).to_raw
    end
end
