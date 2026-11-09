module DomainsHelper
  CATCH_ALL_POLICY_LABELS = {
    "disabled" => "Disabled: reject at SMTP time (recommended)",
    "discard" => "Discard: accept silently, never forward",
    "forward" => "Forward: accept and forward like a registered mailbox"
  }.freeze

  CATCH_ALL_POLICY_SENTENCES = {
    "disabled" => "Mail for an address with no mailbox is rejected",
    "discard" => "Mail for an address with no mailbox is accepted and discarded",
    "forward" => "Mail for an address with no mailbox is forwarded"
  }.freeze

  DNS_RECORD_PROBLEMS = { "missing" => "is missing", "invalid" => "is not valid" }.freeze
  DNS_RECORD_NAMES = { mx: "Inbound", dkim: "DKIM", dmarc: "DMARC", return_path: "Return-Path" }.freeze

  def catch_all_policy_options
    CATCH_ALL_POLICY_LABELS.map { |policy, label| [ label, policy ] }
  end

  def catch_all_policy_sentence(domain)
    CATCH_ALL_POLICY_SENTENCES.fetch(domain.catch_all_policy)
  end

  def domain_rows(domain)
    [
      { icon: "globe", title: "DNS records", hint: domain_dns_records_hint(domain), path: domain_dns_records_path(domain) },
      { icon: "switch", title: "Receiving and sending", hint: domain_switches_hint(domain), path: domain_switches_path(domain) },
      { icon: "email", title: "Mailboxes", hint: domain_count_hint(domain.mailboxes.count, "mailbox", none: "No mailboxes yet"), path: domain_mailboxes_path(domain) },
      { icon: "password", title: "Sending tokens", hint: domain_count_hint(domain.sending_tokens.count, "sending token", none: "None yet"), path: domain_sending_tokens_path(domain) },
      { icon: "bolt", title: "Webhooks", hint: domain_count_hint(domain.webhooks.count, "webhook", none: "None yet"), path: domain_webhooks_path(domain) },
      { icon: "cancel", title: "Blocked phrases", hint: domain_count_hint(domain.blocked_phrase_list.size, "phrase", none: "None"), path: domain_blocked_phrases_path(domain) },
      { icon: "lock", title: "Allowed IPs", hint: domain_count_hint(domain.allowed_ip_list.size, "IP", none: "Any IP can send"), path: domain_allowed_ips_path(domain) },
      { icon: "everyone", title: "People", hint: domain.all_access? ? "Everyone" : pluralize(domain.users.count, "person"), path: domain_people_path(domain) }
    ]
  end

  # Where the domain stands, in a word at the row's end.
  def domain_status_tag(domain)
    word, semantic = domain_status(domain)
    tag.span word, class: "status status--#{semantic}"
  end

  # Under the name, only what needs doing; the check's own sentence stays on the domain's page.
  def domain_dns_problems_line(domain)
    domain_dns_problems(domain).join(" · ")
  end

  # Newest first as [ time, sentence ]: the domain's own events, its last DNS check and who added it.
  def domain_trail(domain)
    lines = domain.events.where(eventable: domain).visible_to(Current.user).ordered.limit(5).map { |event| [ event.created_at, event.description ] }
    lines << [ domain.dns_checked_at, "DNS checked: #{domain.dns_error || "every record was found"}" ] if domain.dns_checked?
    lines << [ domain.created_at, "#{domain.creator.name} added this domain" ]

    lines.sort_by.with_index { |(at, _), index| [ -at.to_f, index ] }.first(5)
  end

  private
    def domain_dns_records_hint(domain)
      safe_join [ domain_verified_label(domain), domain.dns_checked? ? domain_dns_checked_label(domain) : "DNS not checked yet" ], " · "
    end

    def domain_verified_label(domain)
      domain.verified? ? "Verified" : "Not verified"
    end

    def domain_dns_checked_label(domain)
      safe_join [ "checked", local_datetime_tag(domain.dns_checked_at, style: :timeordate) ], " "
    end

    def domain_switches_hint(domain)
      if domain.receiving? && domain.sending?
        "On"
      elsif domain.sending?
        "Receiving off"
      elsif domain.receiving?
        "Sending off"
      else
        "Off"
      end
    end

    def domain_count_hint(count, noun, none:)
      if count.zero?
        none
      else
        pluralize(count, noun)
      end
    end

    def domain_status(domain)
      if !domain.dns_checked?
        [ "Not checked", "muted" ]
      elsif !domain.verified?
        [ "Not verified", "warning" ]
      elsif domain_dns_problems(domain).any?
        [ "DNS problems", "warning" ]
      else
        [ "Verified", "muted" ]
      end
    end

    # A lookup that failed leaves its error beside whatever status the record had before.
    def domain_dns_problems(domain)
      domain.dns_checked_records.filter_map do |record|
        if problem = DNS_RECORD_PROBLEMS[domain.public_send("#{record}_status")]
          "#{DNS_RECORD_NAMES.fetch(record)} record #{problem}"
        elsif domain.public_send("#{record}_error").present?
          "#{DNS_RECORD_NAMES.fetch(record)} record could not be looked up"
        end
      end
    end
end
