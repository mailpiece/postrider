class Relay::MxBackend
  include Relay::Backend

  class << self
    def listener(**options)
      MailGate::MxListener.new(
        backend: new,
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

  def storage_full?
    wrap { MailStorage.full? }
  end

  # Mailboxes, the bounce address and VERP all match case-insensitively, so the route is the recipient in lowercase.
  def route(address)
    recipient = address.downcase
    wrap { recipient if Domain.accepts?(recipient) || Delivery::ReturnPath.address?(recipient) }
  end

  def store(recipient, raw:, digest:, envelope:, **)
    wrap do
      source = Sourced::Source.new(raw, key: "#{envelope.queue_id}#{digest}".downcase)

      if domain = Delivery::ReturnPath.bounce_domain(recipient)
        accept(domain, recipient, source:, digest:, envelope:, &:correlate_bounce_later)
      elsif domain = Domain.for_address(recipient)
        accept(domain, recipient, source:, digest:, envelope:) do |inbound_email|
          if domain.specifically_registered?(recipient) || domain.forward?
            inbound_email.forward_later(ip: envelope.ip, helo: envelope.helo)
          else
            inbound_email.discard
          end
        end
      end
    end
  end

  private
    def accept(domain, rcpt_to, source:, digest:, envelope:)
      Current.with_account(domain.account) do
        InboundEmail.transaction do
          yield InboundEmail.create!(domain:, mail_from: envelope.mail_from, rcpt_to:, source:, digest:,
            remote_ip: envelope.ip, helo: envelope.helo&.truncate(255, omission: ""))
        end
      end
    # A retry after a 451 stores every recipient again; the unique digest keeps one.
    rescue ActiveRecord::RecordNotUnique
    end
end
