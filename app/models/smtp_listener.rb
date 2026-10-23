class SmtpListener < MailSmtp::Server
  include TlsReloadable
  include ErrorReporting

  JUNK_COMMANDS = /\A(?:NOOP|RSET|VRFY|ETRN)\b/i
  MAX_JUNK_COMMANDS = 100
  MAX_SESSION_DURATION = 10.minutes

  # Phases where a line is base64 credential, not a command.
  AUTH_VALUE_PHASES = %i[ auth_plain auth_login_user auth_login_pass ].freeze

  MAILBOX = %r{\A(?<local_part>[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*)@(?<domain>[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*)\z}

  # RFC 5321 §4.5.3.1.2
  MAX_DOMAIN_LENGTH = 255

  def initialize
    super(
      host: Relay.bind_address,
      tls: current_tls,
      max_message_size: message_size_limit,
      read_timeout: 30,
      max_session_duration: MAX_SESSION_DURATION,
      pending_input_limit: 64.kilobytes,
      logger_severity: Relay.smtp_log_level,
      **listener_options
    )
  end

  def connected(session)
    session.banner = "#{hostname} ESMTP"
    session.greeting = hostname
  end

  def build_session
    SmtpSession.new
  end

  def process_line(session, line)
    if junk_command?(session, line)
      session.junk_commands += 1
      raise MailSmtp::ServiceUnavailable, "Too many junk commands" if session.junk_commands > max_junk_commands
    end

    super
  end

  private
    # Skip AUTH continuations: base64 credentials can begin with command letters.
    def junk_command?(session, line)
      AUTH_VALUE_PHASES.exclude?(session.phase) && line.match?(JUNK_COMMANDS)
    end

    # Postfix's smtpd_junk_command_limit under stress.
    def max_junk_commands
      stressed? ? 1 : MAX_JUNK_COMMANDS
    end

    # Empty address is the null reverse-path <> used by bounces (RFC 5321 §4.5.5).
    def sender_in(address)
      raise MailSmtp::InvalidParameters, "Malformed sender address" unless address.empty? || mailbox?(address)

      address
    end

    def recipient_in(address)
      raise MailSmtp::InvalidParameters, "Malformed recipient address" unless mailbox?(address)

      address
    end

    def mailbox?(address)
      if mailbox = MAILBOX.match(address)
        mailbox[:domain].bytesize <= MAX_DOMAIN_LENGTH
      else
        false
      end
    end

    # No PTR lookup on the connection thread; "unknown" is the RFC 5321 §4.4 stand-in.
    def received_header(session)
      "Received: from #{host(session.helo)} (unknown [#{ip(session.remote_ip)}]) " \
        "by #{hostname} with #{received_protocol(session)}; #{Time.now.utc.rfc2822}\r\n"
    end

    def host(value)
      value = value.to_s
      value.length.between?(1, 255) && value.match?(/\A[A-Za-z0-9.\-\[\]:_]+\z/) ? value : "unknown"
    end

    def ip(value)
      value = value.to_s
      value.length.between?(1, 64) && value.match?(/\A[0-9A-Fa-f.:]+\z/) ? value : "unknown"
    end

    def log_accepted(session, bytesize)
      Rails.logger.info "[smtp] #{self.class.name} accepted #{bytesize} bytes from #{envelope_from(session)} to #{session.envelope.to.join(", ")}"
    end

    def envelope_from(session)
      session.envelope.null_sender? ? "<>" : session.envelope.from
    end
end
