module Delivery::Pausable
  extend ActiveSupport::Concern

  BLOCKLIST_WORDING = /spamhaus|block ?list|blacklist|dnsbl|\brbl\b|\bip(?: address)? reputation|reputation of (?:the sending |your )?ip\b|your ip/i

  SLOW_DOWN_WORDING = /rate limited|unusual rate|unexpected volume/i

  included do
    has_one :pause
  end

  def track_recipient_domain_event(action, **particulars)
    if should_track_event?
      Event.create!(eventable: self, domain: eventable_domain, action: "recipient_domain_#{action}", particulars: scrub(recipient_domain: recipient_domain, **particulars))
    end
  end

  private
    # An MX that fails to resolve is left to the delivery, which defers on the same lookup.
    def held_by_pause?
      !relaying? && provider_paused?(destination_hosts.first)
    rescue DnsResolver::TransientError
      false
    end

    def provider_paused?(mx_host)
      Pause.exists?(provider: mail_provider(mx_host))
    end

    def mail_provider(mx_host)
      MailProvider.for(mx_host) || recipient_domain
    end

    # Quoting our IP is not enough: Gmail quotes it when it judges a single message too.
    def blocklisted_by_recipient?(rejection)
      rejection.about_us? && rejection.response.match?(BLOCKLIST_WORDING)
    end

    def told_to_slow_down?(rejection)
      rejection.about_us? && rejection.response.match?(SLOW_DOWN_WORDING)
    end

    # Keyed on the first MX, as the hold is, not on whichever host answered.
    def pause_mail_provider(result, ends_at: nil)
      pause = Pause.create_with(delivery_id: id, recipient_domain: recipient_domain, smtp_output: result.output, ends_at: ends_at)
        .create_or_find_by!(provider: mail_provider(destination_hosts.first))

      if pause.previously_new_record?
        track_recipient_domain_event "paused", provider: pause.provider, smtp_output: result.output
      elsif ends_at.nil?
        pause.update!(ends_at: nil)
      end
    end
end
