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

  DnsRecordItem = Data.define(:record, :title, :status, :error, :found)

  def catch_all_policy_options
    CATCH_ALL_POLICY_LABELS.map { |policy, label| [ label, policy ] }
  end

  def catch_all_policy_sentence(domain)
    CATCH_ALL_POLICY_SENTENCES.fetch(domain.catch_all_policy)
  end

  def domain_settings_rows(domain)
    [
      { icon: "globe", title: "DNS records", hint: domain_state_sentence(domain), path: domain_dns_records_path(domain) },
      { icon: "everyone", title: "People", hint: domain.all_access? ? "Everyone" : pluralize(domain.users.count, "person"), path: domain_people_path(domain) }
    ]
  end

  def domain_dns_records(domain)
    items = [
      dns_record_item(domain.mx_record, "Inbound", domain.mx_status, domain.mx_error),
      dns_record_item(domain.dkim_record, "DKIM", domain.dkim_status, domain.dkim_error),
      dns_record_item(domain.dmarc_record, "DMARC", domain.dmarc_status, domain.dmarc_error),
      dns_record_item(domain.return_path_record, "Return-Path", domain.return_path_status, domain.return_path_error)
    ]

    items.partition { !it.found }.flatten
  end

  # Problems first, each naming its record; the check's own sentence stays on the domain's page.
  def domain_meta(domain)
    if domain.dns_checked?
      problems = domain_dns_problems(domain)
      checked = safe_join [ "checked", local_datetime_tag(domain.dns_checked_at, style: :timeordate) ], " "

      if problems.none?
        safe_join [ domain.verified? ? "Verified" : "Not verified", "DNS OK", checked ], " · "
      elsif domain.verified?
        safe_join [ domain_dns_problems_status(problems), *problems, "Verified", checked ], " · "
      else
        safe_join [ "Not verified", domain_dns_problems_status(problems), *problems, checked ], " · "
      end
    else
      safe_join [ domain.verified? ? "Verified" : "Not verified", "DNS not checked yet" ], " · "
    end
  end

  def domain_state_sentence(domain)
    if domain.dns_checked?
      "#{domain_receiving_sentence(domain)} #{domain_sending_sentence(domain)}"
    else
      "Its DNS records have not been checked yet."
    end
  end

  # Newest first as [ time, sentence ]: the domain's own events, its last DNS check and who added it.
  def domain_trail(domain)
    lines = domain_trail_events(domain).ordered.limit(5).map { |event| [ event.created_at, event.description ] }
    lines << [ domain.dns_checked_at, "DNS checked: #{domain.dns_error || "every record was found"}" ] if domain.dns_checked?
    lines << [ domain.created_at, "#{domain.creator.name} added this domain" ]

    lines.sort_by.with_index { |(at, _), index| [ -at.to_f, index ] }.first(5)
  end

  private
    def dns_record_item(record, title, status, error)
      DnsRecordItem.new(record:, title:, status:, error:, found: status == "ok" && error.blank?)
    end

    def domain_dns_problems_status(problems)
      tag.span "DNS problem".pluralize(problems.size), class: "status status--warning"
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

    # That a domain blocks phrases or limits IPs at all is the admins' to know.
    def domain_trail_events(domain)
      if Current.user.admin?
        domain.events.where(eventable: domain)
      else
        domain.events.where(eventable: domain).where.not(action: %w[ domain_blocked_phrases_changed domain_allowed_ips_changed sending_token_refused ])
      end
    end

    def domain_receiving_sentence(domain)
      if domain.mx_ok?
        "Receives mail."
      else
        "Does not receive mail yet: the inbound record #{dns_record_problem(domain.mx_status, domain.mx_error)}."
      end
    end

    def domain_sending_sentence(domain)
      if domain.verified?
        "Verified for sending."
      else
        "Not verified for sending yet: the DKIM record #{dns_record_problem(domain.dkim_status, domain.dkim_error)}."
      end
    end

    # A lookup that failed leaves no status, only its error.
    def dns_record_problem(status, error)
      if problem = DNS_RECORD_PROBLEMS[status]
        problem
      elsif error.present?
        "could not be looked up (#{error.delete_suffix(".")})"
      else
        "has not been checked"
      end
    end
end
