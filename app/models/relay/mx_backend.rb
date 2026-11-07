class Relay::MxBackend
  include Relay::Backend

  # mailgate's verdict on a message it stores: what authentication found.
  Authenticated = Data.define(:verdicts) do
    def action = :no_action
  end

  class << self
    def listener(**options)
      backend = new

      MailGate::MxListener.new(
        backend:,
        scorer: backend,
        scan_budget: Relay.inbound_authentication_timeout,
        hostname: Relay.helo_hostname,
        host: Relay.bind_address,
        port: Relay.mx_port,
        max_message_size: Relay.max_inbound_message_size,
        max_recipients: Relay.mx_max_recipients,
        max_processings: Relay.mx_max_processings,
        max_processings_per_ip: Relay.mx_max_processings_per_ip,
        max_connections: Relay.mx_max_connections,
        max_connections_per_ip: Relay.mx_max_connections_per_ip,
        max_messages_per_ip: Relay.mx_max_messages_per_ip,
        max_tls_sessions_per_ip: Relay.mx_max_tls_sessions_per_ip,
        stress_threshold: Relay.stress_threshold,
        max_session_duration: Relay.smtp_session_duration,
        # Banner not held back: the October flood review turned down pregreet without postscreen's cache.
        greet_wait: nil,
        logger_severity: Relay.smtp_log_level,
        **options
      )
    end
  end

  def initialize
    @authentications = MailGate::Slots.new(Relay.mx_max_authentications)
  end

  def storage_full?
    wrap { MailStorage.full? }
  end

  # Mailboxes, the bounce address and VERP all match case-insensitively, so the route is the recipient in lowercase.
  def route(address)
    recipient = address.downcase
    wrap { recipient if Domain.accepts?(recipient) || Delivery::ReturnPath.address?(recipient) }
  end

  # mailgate's scorer, once a message before DATA is answered. Bounces to our return path and
  # discards are taken without authenticating anyone. The 451 is raised outside wrap, which reports
  # whatever is raised inside it.
  def check(raw, envelope, budget:)
    if wrap { envelope.rcpt_to.any? { forwarded?(it.downcase) } }
      if verdicts = wrap { settled_verdicts(raw, envelope, within: budget) }
        Authenticated.new(verdicts)
      else
        raise Smtp::Errors::AuthenticationUnsettled, "Authentication unsettled within #{budget}s"
      end
    end
  end

  # A refusal stands; anything else is reported, and the forwarding job authenticates instead.
  def unscored(error, envelope)
    if error.is_a?(MailSmtp::Error)
      raise error
    else
      report_error(error)
    end
  end

  def store(recipient, raw:, digest:, envelope:, verdict:, **)
    wrap do
      source = Sourced::Source.new(raw, key: "#{envelope.queue_id}#{digest}".downcase)

      if domain = Delivery::ReturnPath.bounce_domain(recipient)
        accept(domain, recipient, source:, digest:, envelope:, &:correlate_bounce_later)
      elsif domain = Domain.for_address(recipient)
        accept(domain, recipient, source:, digest:, envelope:, verdict:) do |inbound_email|
          if forwards?(domain, recipient)
            inbound_email.forward_later(ip: envelope.ip, helo: envelope.helo)
          else
            inbound_email.discard
          end
        end
      end
    end
  end

  private
    def settled_verdicts(raw, envelope, within:)
      InboundAuthentication.settled_verdicts(raw, ip: envelope.ip, helo: envelope.helo, mail_from: envelope.mail_from,
        within:, slots: @authentications)
    end

    def forwarded?(recipient)
      if Delivery::ReturnPath.bounce_domain(recipient).nil? && domain = Domain.for_address(recipient)
        forwards?(domain, recipient)
      end
    end

    def forwards?(domain, recipient)
      domain.specifically_registered?(recipient) || domain.forward?
    end

    def accept(domain, rcpt_to, source:, digest:, envelope:, verdict: nil)
      Current.with_account(domain.account) do
        InboundEmail.transaction do
          yield InboundEmail.create!(domain:, mail_from: envelope.mail_from, rcpt_to:, source:, digest:,
            remote_ip: envelope.ip, helo: envelope.helo&.truncate(255, omission: ""), **verdict&.verdicts.to_h)
        end
      end
    # A retry after a 451 stores every recipient again; the unique digest keeps one.
    rescue ActiveRecord::RecordNotUnique
    end
end
