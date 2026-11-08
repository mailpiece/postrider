module MailpiecesHelper
  VERDICT_SEMANTICS = {
    "pass" => "success",
    "softfail" => "warning", "neutral" => "warning",
    "fail" => "error",
    "temperror" => "muted", "permerror" => "muted",
    "none" => "neutral"
  }.freeze

  SMTP_CODE_SEMANTICS = { "2" => "success", "4" => "warning", "5" => "error" }.freeze

  RECEIVED_ACTIONS = %w[ inbound_email_received inbound_email_bounce_received ].freeze

  # Statuses said in other words than their name. Withheld reads Blocked, after the setting that
  # withholds, and inbound mail in flight reads Queued, where the status filter files it.
  STATUS_LABELS = { "withheld" => "Blocked", "exhausted" => "Retries ran out", "pending" => "Queued", "processing" => "Queued" }.freeze

  # A good outcome stays quiet in a list; anything else takes its colour.
  QUIET_STATUSES = %w[ delivered forwarded accepted ].freeze

  GENUINE_STAMP = { verdict: "Genuine", icon: "check", semantic: "success" }.freeze
  UNVERIFIED_STAMP = { verdict: "Not verified", icon: "close", semantic: "warning" }.freeze
  SIGNED_STAMP = { verdict: "Signed", icon: "lock", semantic: "info" }.freeze
  UNCHECKED_STAMP = { verdict: "Not checked", icon: "minus", semantic: "muted", checks: [], note: "no checks recorded" }.freeze

  def smtp_code_tag(code)
    tag.span code, class: "status status--#{SMTP_CODE_SEMANTICS.fetch(code.first, "neutral")}"
  end

  # The reply as the server gave it, less the code shown beside it.
  def smtp_reply_after_code(attempt)
    if attempt.code.present?
      attempt.output.to_s.sub(/\A#{Regexp.escape(attempt.code)}(?:[ -]|\z)/, "")
    else
      attempt.output
    end
  end

  def verdict_tag(verdict, label: nil)
    tag.span [ label, verdict.humanize ].compact.join(" "), class: "status status--#{verdict_semantic(verdict)}"
  end

  def phishing_mark(inbound_email)
    if inbound_email.lookalike_sender?
      phishing_tag "Sent as #{inbound_email.mail_from}: its letters imitate another address, a common phishing trick"
    end
  end

  def contact_phishing_mark(contact)
    if contact.lookalike?
      phishing_tag "Its letters imitate another address, a common phishing trick"
    end
  end

  def mailpiece_avatar_tag(mailpiece)
    name, address, _own = mailpiece_party_details(mailpiece)
    avatar_tag name, address, class: "contact__avatar"
  end

  # Who the row is about: the sender of inbound mail, the recipient of outbound.
  def mailpiece_party(mailpiece)
    name, address, _own = mailpiece_party_details(mailpiece)

    if mailpiece.inbound_email?
      name.presence || address.presence || "No sender"
    else
      "To #{address}"
    end
  end

  # The party's address when the row shows them by name, then the address on our side.
  def mailpiece_addresses(mailpiece)
    name, address, own = mailpiece_party_details(mailpiece)
    safe_join [ (address if name.present?), own ].compact, " · "
  end

  def mailpiece_status(mailpiece)
    mailpiece.inbound_email? ? inbound_status_word(mailpiece.postable) : mailpiece.postable.status
  end

  def status_label(status)
    STATUS_LABELS.fetch(status.to_s) { status.to_s.humanize }
  end

  def mailpiece_status_class(status)
    status.to_s.in?(QUIET_STATUSES) ? "status--muted" : status_class(status)
  end

  # Each status page with a count of what it lists, in the order the filter offers them.
  def mailpiece_status_filters
    { "held" => mailpieces_held_path, "queued" => mailpieces_queued_path, "deferred" => mailpieces_deferred_path,
      "failed" => mailpieces_failed_path, "withheld" => mailpieces_withheld_path, "discarded" => mailpieces_discarded_path }
      .map { |status, path| [ status, path, Current.user.accessible_mailpieces.public_send(status).count ] }
  end

  def envelope_subject(mailpiece)
    mailpiece.subject.presence || "(no subject)"
  end

  def inbound_envelope_status(inbound_email)
    [ status_label(inbound_status_word(inbound_email)), inbound_status_detail(inbound_email) ].compact.join(" · ")
  end

  def delivery_envelope_status(delivery)
    safe_join [ "Outbound", ("#{delivery.attempts.size.ordinalize} attempt" if delivery.attempts.any?),
      (safe_join [ "next retry ", local_datetime_tag(delivery.next_retry_at, style: :datetime) ] if delivery.next_retry_at) ].compact, " · "
  end

  def inbound_outcome_note(inbound_email)
    if inbound_email.forwarded?
      forward_note(inbound_email)
    elsif inbound_email.delivered? || inbound_email.held?
      "not forwarded"
    end
  end

  def delivery_outcome_note(delivery)
    if attempt = delivery.attempts.last
      [ smtp_reply_code(attempt), l(attempt.created_at, format: "%H:%M") ].compact_blank.join(" · ")
    end
  end

  def authentication_stamp(inbound_email)
    verdicts = authentication_verdicts(inbound_email)

    if verdicts.any?
      stamp = inbound_email.authenticated_sender? ? GENUINE_STAMP : UNVERIFIED_STAMP
      stamp.merge(checks: stamp_checks(verdicts), policy: policy_note(inbound_email), note: sealer_note(inbound_email))
    else
      UNCHECKED_STAMP
    end
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
    # The party's name and address, and the address on our side.
    def mailpiece_party_details(mailpiece)
      postable = mailpiece.postable

      if mailpiece.inbound_email?
        [ postable.contact&.name, postable.sender_address, postable.rcpt_to ]
      else
        [ nil, postable.rcpt_to, postable.mail_from ]
      end
    end

    def phishing_tag(title)
      tag.span "Phishing?", class: "envelope__phishing", title: title
    end

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
        forward_note(inbound_email)
      elsif inbound_email.delivered?
        "not forwarded"
      end
    end

    def forward_note(inbound_email)
      if forward_to = event_particular(inbound_email, "inbound_email_forwarded", "forward_to")
        "to #{forward_to}"
      end
    end

    # Reads the loaded events, so a list that preloads them asks nothing more.
    def event_particular(inbound_email, action, key)
      inbound_email.events.find { |event| event.action == action }&.particulars&.dig(key)
    end

    # The reply code with its enhanced status, "250 2.0.0", when the reply gives one.
    def smtp_reply_code(attempt)
      [ attempt.code, smtp_reply_after_code(attempt).to_s[/\A\d\.\d{1,3}\.\d{1,3}\b/] ].compact_blank.join(" ").presence
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
      mailpiece = inbound_email.matched_delivery&.mailpiece

      if mailpiece && Current.user.accessible_mailpieces.include?(mailpiece)
        safe_join [ "Matched to ", link_to("the delivery it bounced", mailpiece_path(mailpiece)), "." ]
      else
        "Matched to the delivery it bounced."
      end
    end

    def held_explanation(reason)
      if reason = Event::Description::HELD_REASONS[reason]
        "Held because #{reason}."
      else
        "Held."
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

    # The verdict already says what passed, so passes go bare, two to a line.
    def stamp_checks(verdicts)
      verdicts.group_by { |_, verdict| verdict }.flat_map do |verdict, checks|
        names = checks.map(&:first)

        case verdict
        when "pass" then names.each_slice(2).map { |pair| pair.join(" ") }
        when "fail" then "#{names.join(" ")} failed"
        else
          "#{names.join(" ")} #{verdict}"
        end
      end
    end

    def policy_note(inbound_email)
      "p=#{inbound_email.dmarc_policy}" if inbound_email.dmarc_policy.present?
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
