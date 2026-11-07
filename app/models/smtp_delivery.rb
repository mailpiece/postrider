require "ipaddr"
require "mailauth"
require "net/smtp"
require "openssl"
require "stringio"

class SmtpDelivery
  # MX records carry no port; RFC 5321 relay delivery is 25.
  SMTP_PORT = 25

  # Each address dialed, to connect, greet and finish STARTTLS, so one that hangs leaves the next its turn.
  OPEN_TIMEOUT = 30

  # Each command once connected: MAIL, RCPT, and closing.
  COMMAND_TIMEOUT = 60

  DATA_TIMEOUT = 10.minutes.to_i

  # A domain listing hundreds of hosts or addresses can't hold a worker for hours.
  MAX_MX_HOSTS = 5

  MAX_MX_ADDRESSES = 5

  # Replies arrive as bytes; keep them as text so an attempt can always be saved.
  Result = Struct.new(:status, :code, :output, :mx_host, :transcript) do
    def output
      utf8 self[:output]
    end

    def transcript
      utf8 self[:transcript]
    end

    private
      def utf8(text)
        text&.dup&.force_encoding(Encoding::UTF_8)&.scrub
      end
  end

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
          if smtputf8_required?(smtp)
            # Another MX may offer it; only when none does is the mailbox out of reach.
            @smtputf8_refusal = Result.new(:session_fail, nil, "5.6.7 #{host} does not offer SMTPUTF8, which the non-ASCII mailbox #{@rcpt_to} needs", host, transcript.string)
          else
            return send_message(smtp, host, transcript)
          end
        ensure
          finish smtp
        end
      end
    end

    @smtputf8_refusal || unavailable_result
  end

  private
    def targets
      if @relay
        host, port = @relay
        [ [ host, host, port ] ]
      else
        @hosts.first(MAX_MX_HOSTS).lazy
          .flat_map { |host| Array(targets_for(host)) }
          .uniq { |_, address, _| address }
          .take(MAX_MX_ADDRESSES)
      end
    end

    def targets_for(host)
      if prohibited_by_policy?(host)
        record_connection_error(host, "not permitted by MTA-STS policy")
      elsif (addresses = Surfguard.resolve_public_ips(host)).empty?
        record_connection_error(host, "no public address")
      elsif (addresses = addresses.select { |address| sendable?(address) }).empty?
        record_connection_error(host, "no #{own_addresses.first.ipv6? ? "IPv6" : "IPv4"} address")
      else
        addresses.map { |address| [ host, address, SMTP_PORT ] }
      end
    rescue Surfguard::Unresolvable
      record_connection_error(host, "could not be resolved")
    end

    # Without a bound sending IP, the relay hostname's own addresses tell which families we send from.
    def sendable?(address)
      own_addresses.none? || own_addresses.any? { |own| own.ipv6? == IPAddr.new(address).ipv6? }
    end

    def own_addresses
      @own_addresses ||= (@sending_ip ? [ @sending_ip.address ] : Relay.own_addresses).map { |address| IPAddr.new(address) }
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
      Timeout.timeout(OPEN_TIMEOUT) { smtp.start(helo_hostname) }
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
      Timeout.timeout(COMMAND_TIMEOUT) { smtp.rcptto(recipient(smtp)) }
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

    # A mailbox name has no ASCII form; a domain has its A-label (RFC 5890).
    def smtputf8_required?(smtp)
      !@rcpt_to.rpartition("@").first.ascii_only? && !smtp.capable?("SMTPUTF8")
    end

    def recipient(smtp)
      if @rcpt_to.ascii_only? || smtp.capable?("SMTPUTF8")
        @rcpt_to
      else
        local_part, _, domain = @rcpt_to.rpartition("@")
        "#{local_part}@#{MailAuth::Domain.normalize(domain)}"
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
