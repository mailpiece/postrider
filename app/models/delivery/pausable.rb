module Delivery::Pausable
  extend ActiveSupport::Concern

  BLOCKLIST_WORDING = /spamhaus|block ?list|blacklist|dnsbl|\brbl\b|\bip(?: address)? reputation|reputation of (?:the sending |your )?ip\b|your ip/i

  included do
    has_one :pause
  end

  def track_recipient_domain_event(action, **particulars)
    if should_track_event?
      Event.create!(eventable: self, domain: eventable_domain, action: "recipient_domain_#{action}", particulars: scrub(recipient_domain: recipient_domain, **particulars))
    end
  end

  private
    def held_by_pause?
      !relaying? && recipient_domain_paused?
    end

    def recipient_domain_paused?
      Pause.exists?(recipient_domain: recipient_domain)
    end

    # Quoting our IP is not enough: Gmail quotes it when it judges a single message too.
    def blocklisted_by_recipient?(rejection)
      rejection.about_us? && rejection.response.match?(BLOCKLIST_WORDING)
    end

    def pause_recipient_domain(smtp_output)
      pause = Pause.create_with(delivery_id: id, smtp_output: smtp_output).create_or_find_by!(recipient_domain: recipient_domain)

      if pause.previously_new_record?
        track_recipient_domain_event "paused", smtp_output: smtp_output
      end
    end
end
