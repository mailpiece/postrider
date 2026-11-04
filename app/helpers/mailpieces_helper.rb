module MailpiecesHelper
  # Plain answers to "why is this here and what do I do about it", since the protocol
  # words below mean nothing to someone deciding whether to release a message.
  # Past tense: a reason is what we concluded at the hold, and a contact may be approved since.
  HOLD_EXPLANATIONS = {
    "denied_sender" => "Held because this sender was not approved.",
    "unidentified_sender" => "Held because we couldn't read a From address on it.",
    "unauthenticated_sender" => "Held because we couldn't confirm the sender is genuine.",
    "forwarding_loop" => "Held because it looked like a forwarding loop."
  }.freeze

  VERDICT_SEMANTICS = {
    "pass" => "success",
    "softfail" => "warning", "neutral" => "warning",
    "fail" => "error",
    "temperror" => "muted", "permerror" => "muted",
    "none" => "neutral"
  }.freeze

  SMTP_CODE_SEMANTICS = { "2" => "success", "4" => "warning", "5" => "error" }.freeze

  RECEIVED_ACTIONS = %w[ inbound_email_received inbound_email_bounce_received ].freeze

  GENUINE_STAMP = { verdict: "Genuine", icon: "check", semantic: "success" }.freeze
  UNVERIFIED_STAMP = { verdict: "Not verified", icon: "close", semantic: "warning" }.freeze
  SIGNED_STAMP = { verdict: "Signed", icon: "lock", semantic: "info" }.freeze

  def smtp_code_tag(code)
    tag.span code, class: "status status--#{SMTP_CODE_SEMANTICS.fetch(code.first, "neutral")}"
  end

  def verdict_tag(verdict, label: nil)
    tag.span [ label, verdict.humanize ].compact.join(" "), class: "status status--#{verdict_semantic(verdict)}"
  end

  def mailpiece_status(mailpiece)
    mailpiece.inbound_email? ? inbound_status_word(mailpiece.postable) : mailpiece.postable.status
  end

  def inbound_envelope_status(inbound_email)
    [ inbound_status_word(inbound_email).humanize, inbound_status_detail(inbound_email) ].compact.join(" · ")
  end

  def delivery_envelope_status(delivery)
    safe_join [ "Outbound", (pluralize(delivery.attempts.size, "attempt") if delivery.attempts.any?),
      (safe_join [ "next retry ", local_datetime_tag(delivery.next_retry_at, style: :datetime) ] if delivery.next_retry_at) ].compact, " · "
  end

  def authentication_stamp(inbound_email)
    verdicts = authentication_verdicts(inbound_email)

    if verdicts.any?
      (inbound_email.authenticated_sender? ? GENUINE_STAMP : UNVERIFIED_STAMP).merge(checks: stamp_checks(verdicts), note: sealer_note(inbound_email))
    end
  end

  def mailpiece_stamp(mailpiece)
    mailpiece.inbound_email? ? authentication_stamp(mailpiece.postable) : SIGNED_STAMP
  end

  def signature_stamp(delivery)
    if delivery.message.signable?
      SIGNED_STAMP.merge(checks: [ "DKIM" ], note: delivery.domain.name)
    else
      SIGNED_STAMP.merge(checks: [ "ARC" ], note: Relay.hostname)
    end
  end

  # Newest first as [ time, sentence ]. Lines that share a time keep the order they are added in.
  def inbound_email_trail(inbound_email)
    events = inbound_email.events.ordered.to_a
    received = events.find { |event| event.action.in?(RECEIVED_ACTIONS) }

    lines = (events - [ received ]).map { |event| [ event.created_at, inbound_event_sentence(event) ] }

    if inbound_email.delivered? && events.none? { |event| event.action == "inbound_email_forwarded" }
      if sentence = delivered_sentence(inbound_email, received)
        lines << [ inbound_email.forwarded_at || inbound_email.updated_at, sentence ]
      end
    end

    if inbound_email.held? && events.none? { |event| event.action == "inbound_email_held" }
      lines << [ inbound_email.updated_at, held_explanation(nil) ]
    end

    lines << [ inbound_email.created_at, received_sentence(received) ]

    lines.sort_by.with_index { |(at, _), index| [ -at.to_f, index ] }
  end

  private
    def verdict_semantic(verdict)
      VERDICT_SEMANTICS.fetch(verdict, "neutral")
    end

    def inbound_status_word(inbound_email)
      if inbound_email.forwarded?
        "forwarded"
      elsif inbound_email.delivered?
        "accepted"
      elsif inbound_email.bounced?
        "discarded"
      else
        inbound_email.status
      end
    end

    def inbound_status_detail(inbound_email)
      if inbound_email.held?
        Event::Description::HELD_REASONS[event_particular(inbound_email, "inbound_email_held", "reason")]
      elsif inbound_email.forwarded?
        if forward_to = event_particular(inbound_email, "inbound_email_forwarded", "forward_to")
          "to #{forward_to}"
        end
      elsif inbound_email.delivered?
        "not forwarded"
      end
    end

    def event_particular(inbound_email, action, key)
      inbound_email.events.find_by(action: action)&.particulars&.dig(key)
    end

    def inbound_event_sentence(event)
      case event.action
      when "inbound_email_forwarded" then forwarded_sentence(event.particulars["forward_to"])
      when "inbound_email_held"      then held_explanation(event.particulars["reason"])
      when "inbound_email_scored"    then InboundEmail::SpamCheck.new(event.particulars).sentence
      else
        "#{event.description}."
      end
    end

    def forwarded_sentence(forward_to)
      forward_to.present? ? "Forwarded to #{forward_to}." : "Forwarded."
    end

    # Delivered with no forwarded event. Mail to the bounce address says so in its receipt,
    # and only a bounce matched to its delivery is processed without a receipt.
    def delivered_sentence(inbound_email, received)
      if inbound_email.forwarded?
        forwarded_sentence(nil)
      elsif received.nil?
        matched_bounce_sentence(inbound_email)
      elsif received.action == "inbound_email_received"
        "Accepted. Forwarding was not on for this address."
      end
    end

    def matched_bounce_sentence(inbound_email)
      delivery = Delivery::ReturnPath.find_delivery(inbound_email.rcpt_to)

      if delivery && mailpiece = Current.user.accessible_mailpieces.find_by(postable: delivery)
        safe_join [ "Matched to ", link_to("the delivery it bounced", mailpiece_path(mailpiece)), "." ]
      else
        "Matched to the delivery it bounced."
      end
    end

    def held_explanation(reason)
      HOLD_EXPLANATIONS.fetch(reason, "Held.")
    end

    def authentication_verdicts(inbound_email)
      {
        "SPF" => inbound_email.spf,
        "DKIM" => inbound_email.dkim,
        "DMARC" => inbound_email.dmarc,
        "ARC" => inbound_email.arc.presence_in(%w[ pass fail ])
      }.compact_blank
    end

    def stamp_checks(verdicts)
      verdicts.group_by { |_, verdict| verdict }.map do |verdict, checks|
        names = checks.map(&:first).join(" ")

        case verdict
        when "pass" then "#{names} passed"
        when "fail" then "#{names} failed"
        else
          "#{names} #{verdict}"
        end
      end
    end

    def sealer_note(inbound_email)
      if inbound_email.arc_sealer.present?
        inbound_email.arc == "pass" ? "via #{inbound_email.arc_sealer}" : "#{inbound_email.arc_sealer} seal failed"
      end
    end

    def received_sentence(event)
      lead = event&.action == "inbound_email_bounce_received" ? "Received a bounce" : "Received"
      host, ip = event&.particulars&.values_at("remote_host", "remote_ip")

      if host.present? && ip.present?
        "#{lead} from #{host} (#{ip})."
      elsif origin = host.presence || ip.presence
        "#{lead} from #{origin}."
      else
        "#{lead}."
      end
    end
end
