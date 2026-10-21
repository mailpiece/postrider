module MailpiecesHelper
  # Plain answers to "why is this here and what do I do about it", since the protocol
  # words below mean nothing to someone deciding whether to release a message.
  # Past tense: a reason is what we concluded at the hold, and a contact may be approved since.
  HOLD_EXPLANATIONS = {
    "denied_sender" => "Held because this sender was not approved",
    "unidentified_sender" => "Held because we couldn't read a From address on it",
    "unauthenticated_sender" => "Held because we couldn't confirm the sender is genuine",
    "forwarding_loop" => "Held because it looked like a forwarding loop"
  }.freeze

  DMARC_POLICY_REQUESTS = {
    "none" => "take no action on mail that fails DMARC",
    "quarantine" => "treat mail that fails DMARC as suspicious",
    "reject" => "reject mail that fails DMARC"
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

  def smtp_code_tag(code)
    tag.span code, class: "status status--#{SMTP_CODE_SEMANTICS.fetch(code.first, "neutral")}"
  end

  def verdict_tag(verdict, label: nil)
    tag.span [ label, verdict.humanize ].compact.join(" "), class: "status status--#{verdict_semantic(verdict)}"
  end

  def inbound_status_tag(inbound_email, **options)
    status_tag inbound_status_word(inbound_email), **options
  end

  def mailpiece_meta(mailpiece)
    postable = mailpiece.postable
    status = mailpiece.inbound_email? ? inbound_status_word(postable) : postable.status

    safe_join [ row_status(status), mailpiece.inbound_email? ? "Received" : "Sent", "#{postable.mail_from} → #{postable.rcpt_to}",
      local_datetime_tag(mailpiece.created_at, style: :timeordate) ], " · "
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

    lines.concat authentication_sentences(inbound_email).map { |sentence| [ inbound_email.created_at, sentence ] }
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

    def inbound_event_sentence(event)
      case event.action
      when "inbound_email_forwarded" then [ "Forwarded", event.particulars["forward_to"].presence ].compact.join(" to ")
      when "inbound_email_held"      then held_explanation(event.particulars["reason"])
      else
        event.description
      end
    end

    # Delivered with no forwarded event. Mail to the bounce address says so in its receipt,
    # and only a bounce matched to its delivery is processed without a receipt.
    def delivered_sentence(inbound_email, received)
      if inbound_email.forwarded?
        "Forwarded"
      elsif received.nil?
        matched_bounce_sentence(inbound_email)
      elsif received.action == "inbound_email_received"
        "Accepted. Forwarding was not on for this address."
      end
    end

    def matched_bounce_sentence(inbound_email)
      delivery = Delivery::ReturnPath.find_delivery(inbound_email.rcpt_to)

      if delivery && mailpiece = Current.user.accessible_mailpieces.find_by(postable: delivery)
        safe_join [ "Matched to ", link_to("the delivery it bounced", mailpiece_path(mailpiece)) ]
      else
        "Matched to the delivery it bounced"
      end
    end

    def held_explanation(reason)
      HOLD_EXPLANATIONS.fetch(reason, "Held")
    end

    def authentication_sentences(inbound_email)
      [ sender_sentence(inbound_email), dmarc_policy_sentence(inbound_email), arc_sealer_sentence(inbound_email) ].compact
    end

    def sender_sentence(inbound_email)
      verdicts = authentication_verdicts(inbound_email)

      if verdicts.any?
        lead = inbound_email.authenticated_sender? ? "The sender is genuine" : "The sender is not verified"
        "#{lead}: #{verdict_clauses(verdicts).join(", ")}"
      end
    end

    def authentication_verdicts(inbound_email)
      {
        "SPF" => inbound_email.spf,
        "DKIM" => inbound_email.dkim,
        "DMARC" => inbound_email.dmarc,
        "ARC" => inbound_email.arc.presence_in(%w[ pass fail ])
      }.compact_blank
    end

    def verdict_clauses(verdicts)
      verdicts.group_by { |_, verdict| verdict }.map do |verdict, checks|
        names = checks.map(&:first).to_sentence(last_word_connector: " and ")

        case verdict
        when "pass" then "#{names} passed"
        when "fail" then "#{names} failed"
        else
          "#{names} returned #{verdict}"
        end
      end
    end

    def dmarc_policy_sentence(inbound_email)
      if request = DMARC_POLICY_REQUESTS[inbound_email.dmarc_policy]
        "#{Domain.name_for(inbound_email.from_address) || "The From domain"} asks receivers to #{request}"
      end
    end

    def arc_sealer_sentence(inbound_email)
      if inbound_email.arc_sealer.present?
        if inbound_email.arc == "pass"
          "Passed through #{inbound_email.arc_sealer}"
        else
          "Carries a seal in the name of #{inbound_email.arc_sealer} that did not verify"
        end
      end
    end

    def received_sentence(event)
      lead = event&.action == "inbound_email_bounce_received" ? "Received a bounce" : "Received"
      host, ip = event&.particulars&.values_at("remote_host", "remote_ip")

      if host.present? && ip.present?
        "#{lead} from #{host} (#{ip})"
      elsif origin = host.presence || ip.presence
        "#{lead} from #{origin}"
      else
        lead
      end
    end
end
