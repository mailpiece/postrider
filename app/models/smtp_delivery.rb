require "net/smtp"
require "openssl"
require "stringio"

class SmtpDelivery
  # MX records carry no port; RFC 5321 relay delivery is 25.
  SMTP_PORT = 25

  OPEN_TIMEOUT = 10

  COMMAND_TIMEOUT = 30

  DATA_TIMEOUT = 10.minutes.to_i

  # Postfix's smtp_mx_address_limit: a domain listing hundreds of hosts can't hold a worker for hours.
  MAX_MX_HOSTS = 5

  Result = Struct.new(:status, :code, :output, :mx_host, :transcript)

  TLS_CONTEXT = OpenSSL::SSL::SSLContext.new.tap do |context|
    context.verify_mode = OpenSSL::SSL::VERIFY_NONE
    context.setup
  end

  # Opportunistic TLS usually won't verify; VERIFY_NONE stays the default.
  VERIFIED_TLS_CONTEXT = OpenSSL::SSL::SSLContext.new.tap do |context|
    context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
    context.min_version = OpenSSL::SSL::TLS1_2_VERSION
    context.setup
  end

  def initialize(raw:, mail_from:, rcpt_to:, hosts:, policy: nil)
    @raw = raw
    @mail_from = mail_from
    @rcpt_to = rcpt_to
    @hosts = hosts
    @policy = policy
    @connection_errors = []
    @relay = Relay.outbound_relay
    @sending_ip = Relay.default_sending_ip unless @relay
  end

  def deliver
    # Normalize once so hostname match and SNI stay in lockstep.
    targets.each do |name, address, port|
      host = DnsResolver.normalize(name)
      transcript = StringIO.new
      if smtp = connect(host, address, port, transcript)
        begin
          return send_message(smtp, host, transcript)
        ensure
          finish smtp
        end
      end
    end

    unavailable_result
  end

  private
    def targets
      if @relay
        host, port = @relay
        [ [ host, host, port ] ]
      else
        @hosts.first(MAX_MX_HOSTS).lazy.filter_map { |host| target_for(host) }
      end
    end

    def target_for(host)
      if prohibited_by_policy?(host)
        record_connection_error(host, "not permitted by MTA-STS policy")
      elsif address = Surfguard.resolve_public_ips(host).first
        [ host, address, SMTP_PORT ]
      else
        record_connection_error(host, "no public address")
      end
    rescue Surfguard::Unresolvable
      record_connection_error(host, "could not be resolved")
    end

    def prohibited_by_policy?(host)
      @policy&.enforce? && !@policy.allows?(host)
    end

    def connect(host, address, port, transcript, starttls: true)
      smtp = Net::SMTP.new(address, port)
      smtp.source_address = @sending_ip&.address
      smtp.open_timeout = OPEN_TIMEOUT
      smtp.read_timeout = DATA_TIMEOUT
      smtp.debug_output = transcript
      if require_tls?(host)
        # SNI/verify the MX name, not the dialed IP; refuse plaintext (auto would allow it).
        smtp.tls_hostname = host
        smtp.enable_starttls(VERIFIED_TLS_CONTEXT)
      elsif starttls
        smtp.enable_starttls_auto(TLS_CONTEXT)
      else
        smtp.disable_starttls
      end
      Timeout.timeout(COMMAND_TIMEOUT) { smtp.start(helo_hostname) }
      smtp
    rescue OpenSSL::SSL::SSLError => error
      finish smtp
      if starttls && !require_tls?(host)
        connect(host, address, port, transcript, starttls: false)
      else
        record_connection_error(host, error.message.strip)
      end
    rescue StandardError => error
      finish smtp
      record_connection_error(host, error.message.strip)
    end

    # Operator smarthost may keep a self-signed cert.
    def require_tls?(host)
      !@relay && (@policy&.enforce? || host.end_with?(*Relay.require_tls_mx_suffixes))
    end

    def helo_hostname
      @sending_ip&.helo || Relay.helo_hostname
    end

    def finish(smtp)
      Timeout.timeout(COMMAND_TIMEOUT) { smtp.finish }
    rescue StandardError
      nil
    end

    def record_connection_error(host, message)
      @connection_errors << "#{host}: #{message}"
      nil
    end

    def send_message(smtp, host, transcript)
      Timeout.timeout(COMMAND_TIMEOUT) { smtp.mailfrom(sender(smtp)) }
      Timeout.timeout(COMMAND_TIMEOUT) { smtp.rcptto(@rcpt_to) }
      response = Timeout.timeout(DATA_TIMEOUT) { smtp.data(@raw) }
      Result.new(:sent, response.status, response.string.strip, host, transcript.string)
    rescue Net::SMTPFatalError => error
      failure(:hard_fail, error, host, transcript)
    rescue Net::SMTPSyntaxError, Net::SMTPAuthenticationError => error
      failure(:session_fail, error, host, transcript)
    rescue Net::SMTPServerBusy, Net::SMTPUnknownError,
           Net::ReadTimeout, Timeout::Error, OpenSSL::SSL::SSLError, SocketError, SystemCallError => error
      failure(:soft_fail, error, host, transcript)
    end

    def sender(smtp)
      if !@rcpt_to.ascii_only? && smtp.capable?("SMTPUTF8")
        Net::SMTP::Address.new(@mail_from, "SMTPUTF8")
      else
        @mail_from
      end
    end

    def failure(status, error, host, transcript)
      Result.new(status, failure_code(error), error.message.strip, host, transcript.string)
    end

    def failure_code(error)
      if error.respond_to?(:response) && error.response
        error.response.status
      else
        error.message[/\A\d{3}\b/]
      end
    end

    def unavailable_result
      message = "No SMTP servers available"
      message += ": #{@connection_errors.join("; ")}" if @connection_errors.any?
      Result.new(:soft_fail, nil, message, nil, nil)
    end
end
