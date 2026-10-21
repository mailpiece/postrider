require "mailauth"

module InboundEmail::Forwarding
  extend ActiveSupport::Concern

  TRACE_HEADER = "X-PostRider-Forwarded"
  MAX_RECEIVED_HOPS = 25

  included do
    belongs_to :contact, optional: true

    # Contact mail is read through the contact; pairing keeps that scope honest.
    validate :contact_belongs_to_domain
  end

  def forwarding_applies?
    !to_bounce_address? && forwarding_mailbox.present?
  end

  def forward_or_hold
    update! contact: Contact.for_sender(domain, from_address, name: from_name)

    if forwardable?
      forward_to_destination
    else
      hold
    end
  end

  def forward_held
    if forwardable?
      forward_to_destination
    end
  end

  # Delivered also covers mail accepted without a forward. A contact is only filed where
  # forwarding applies, and from there only a forward ends delivered.
  def forwarded?
    delivered? && contact_id?
  end

  # From is only believed when DMARC/DKIM/SPF alignment vouch for it.
  def authenticated_sender?
    dmarc == "pass" || from_aligned?
  end

  def from_address
    parsed_email.from_address
  end

  def from_name
    parsed_email.from_name
  end

  private
    def contact_belongs_to_domain
      if contact && contact.domain_id != domain_id
        errors.add(:contact, "is not a contact of this domain")
      end
    end

    def forwardable?
      contact&.approved? && authenticated_sender? && forwarding_mailbox.present? && !forwarding_loop?
    end

    def forwarding_mailbox
      @forwarding_mailbox ||= domain.mailboxes.forwarding.find_by(local_part: rcpt_to.to_s.split("@", 2).first.to_s.downcase)
    end

    def forward_to_destination
      destination = forwarding_mailbox.forward_to

      transaction do
        Message.submit_raw(domain: domain, mail_from: mail_from.presence || from_address,
          raw: forwardable_raw(destination), tags: [ "forwarded" ], recipients: [ destination ], origin: :forwarded)
        update! status: :delivered, forwarded_at: Time.current
        track_event "forwarded", rcpt_to: rcpt_to, forward_to: destination
      end
    end

    def forwardable_raw(destination)
      sealed(InboundEmail::ForwardingHeaders.new(self, destination).prepended_to(raw))
    end

    # Forwarding breaks SPF and often DKIM, so we seal what we concluded before it does.
    # A message we can't seal still forwards: the seal is a record, not a condition.
    def sealed(forwardable)
      Relay::SealingKey.instance.seal(forwardable,
        authentication_results: sealed_results, chain_status: sealed_chain_status)
    rescue StandardError => error
      Rails.error.report(error, severity: :warning)
      forwardable
    end

    # Mail received before we stored the value still has to state an authserv-id.
    def sealed_results
      authentication_results.presence ||
        MailAuth::AuthenticationResults.new(spf: nil, dkim: nil, dmarc: nil, mta: Relay.hostname).to_s
    end

    # RFC 8617 §5.1.3 closes a chain already sealed cv=fail, but one overall status can't
    # tell that from a chain that merely failed here, so we seal it (§5.1.2) either way.
    def sealed_chain_status
      arc.presence_in(MailAuth::Arc::CHAIN_STATUSES) || "none"
    end

    def hold
      transaction do
        update! status: :held
        track_event "held", rcpt_to: rcpt_to, reason: hold_reason
      end
    end

    def hold_reason
      if contact.nil?
        "unidentified_sender"
      elsif contact.denied?
        "denied_sender"
      elsif !authenticated_sender?
        "unauthenticated_sender"
      else
        "forwarding_loop"
      end
    end

    def forwarding_loop?
      header_block.match?(/^#{TRACE_HEADER}:/i) || header_block.scan(/^Received:/i).count >= MAX_RECEIVED_HOPS
    end

    def header_block
      raw.to_s.split(/\r?\n\r?\n/, 2).first.to_s
    end
end
