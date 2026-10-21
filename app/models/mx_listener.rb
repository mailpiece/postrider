class MxListener < SmtpListener
  def mail_from(_session, address)
    sender_in(address)
  end

  def rcpt_to(session, address)
    if session.envelope.to.size >= Relay.mx_max_recipients
      raise MailSmtp::TooManyRecipients, "Too many recipients, maximum is #{Relay.mx_max_recipients}"
    end

    # Domainless <Postmaster> (RFC 5321 §4.5.1) is unroutable; reject before recipient_in calls it syntax.
    raise Smtp::Errors::RelayDenied, "Relay access denied for #{address}" if bare_postmaster?(address)

    address = recipient_in(address)

    if Domain.accepts?(address) || Delivery::ReturnPath.address?(address)
      address
    else
      raise Smtp::Errors::RelayDenied, "Relay access denied for #{address}"
    end
  end

  def receive(session, io)
    body = io.read
    raise Smtp::Errors::LoopDetected, "Loop detected" if looping?(body)

    source = Sourced::Source.new(received_header(session) + InboundAuthentication.strip(body))
    digest = content_digest(session, body)

    Rails.application.executor.wrap do
      session.envelope.to.each do |rcpt_to|
        receive_for(rcpt_to, mail_from: session.envelope.from, source: source, digest: digest,
          ip: session.remote_ip, helo: session.helo)
      end
    end

    log_accepted(session, body.bytesize)
  rescue MailSmtp::Error
    raise
  rescue StandardError => error
    Rails.error.report(error, severity: :error)
    raise MailSmtp::LocalError, "Temporary local error, please retry"
  end

  private
    def bare_postmaster?(address)
      address.casecmp?("postmaster")
    end

    def hostname
      Relay.helo_hostname
    end

    def received_protocol(session)
      session.encrypted? ? "ESMTPS" : "ESMTP"
    end

    def listener_options
      {
        port: Relay.mx_port,
        max_processings: Relay.mx_max_processings,
        max_connections: Relay.mx_max_connections,
        max_connections_per_ip: Relay.mx_max_connections_per_ip,
        auth: :disabled,
        starttls: :optional,
        # Tolerate missing angle brackets: a 501 is permanent and costs mail from old senders.
        # Content is still held to the mailbox grammar; submission stays strict.
        strict_path: false,
        # Safe: inbound ends as a webhook, no onward 7-bit downgrade debt.
        eight_bit_mime: true
      }
    end

    def message_size_limit
      Relay.max_inbound_message_size
    end

    def looping?(body)
      own_stamps = header_section(body).scan(/^Received:.*\bby #{Regexp.escape(Relay.helo_hostname)}\b/i)
      own_stamps.count > 4
    end

    def header_section(data)
      data.split(/\r?\n\r?\n/, 2).first.to_s.gsub(/\r?\n[ \t]+/, " ")
    end

    def content_digest(session, body)
      Digest::SHA256.new.update("#{session.envelope.from}\n").update(body).hexdigest
    end

    def receive_for(rcpt_to, mail_from:, source:, digest:, ip:, helo:)
      if domain = Delivery::ReturnPath.bounce_domain(rcpt_to)
        accept(domain, mail_from:, rcpt_to:, source:, digest:, &:correlate_bounce_later)
      elsif domain = Domain.for_address(rcpt_to)
        accept(domain, mail_from:, rcpt_to:, source:, digest:) do |inbound_email|
          if domain.specifically_registered?(rcpt_to) || domain.forward?
            inbound_email.forward_later(ip:, helo:)
          else
            inbound_email.discard
          end
        end
      end
    end

    def accept(domain, mail_from:, rcpt_to:, source:, digest:)
      Current.with_account(domain.account) do
        InboundEmail.transaction do
          yield InboundEmail.create!(domain:, mail_from:, rcpt_to:, source:, digest:)
        end
      end
    rescue ActiveRecord::RecordNotUnique
    end
end
