require "socket"
require "net/smtp"
require "mailresolver/testing"

module SmtpTestHelper
  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def start_listener(port_env, port)
    with_env(port_env => port, BIND_ADDRESS: "127.0.0.1") { yield.tap(&:start) }
  ensure
    wait_until_listening(port)
  end

  # No real DNS: a client's address has no reverse DNS name unless a test's resolver gives it one.
  def start_mx_listener(port, **options)
    start_listener("MX_PORT", port) { Relay::MxBackend.listener(resolver: MailResolver::Testing::FakeResolver.new, **options) }
  end

  def start_submission_listener(port, **options)
    start_listener("SUBMISSION_PORT", port) { Relay::SubmissionBackend.listener(**options) }
  end

  def stop_listener(listener)
    listener&.stop
  end

  # The bytes a receiver keeps from Net::SMTP's DATA: its own line endings, dot-stuffing undone.
  def as_sent_over_smtp(raw)
    wire = StringIO.new
    Net::InternetMessageIO.new(wire).write_message(raw)
    wire.string.b.delete_suffix(".\r\n").gsub(/^\.\./n, ".")
  end

  def envelope(**overrides)
    MailGate::Envelope.new(ip: "203.0.113.1", hostname: "unknown", helo: "client.example", mail_from: "sender@example.com",
      rcpt_to: [], tls_version: nil, tls_cipher: nil, queue_id: SecureRandom.alphanumeric(12).upcase, **overrides)
  end

  def mx_deliver(port:, from:, to:, raw:, helo: "test.client.example")
    smtp = Net::SMTP.new("127.0.0.1", port)
    smtp.disable_starttls
    smtp.start(helo) { smtp.send_message(raw, from, to) }
  end

  def submission_deliver(port:, from:, to:, token: DomainTestHelper::SENDING_TOKEN, username: SendingToken::SMTP_USERNAME, message: nil, auth_type: :plain)
    with_starttls_smtp(port) do |smtp|
      smtp.authenticate(username, token, auth_type)
      smtp.send_message(message || "From: #{from}\r\nTo: #{to}\r\nSubject: Hi\r\n\r\nBody.\r\n", from, to)
    end
  end

  def with_starttls_smtp(port)
    smtp = Net::SMTP.new("127.0.0.1", port)
    smtp.enable_starttls(insecure_tls_context)
    smtp.start { yield smtp }
  end

  def insecure_tls_context
    OpenSSL::SSL::SSLContext.new.tap { |context| context.verify_mode = OpenSSL::SSL::VERIFY_NONE }
  end

  def read_smtp_response(socket)
    loop do
      line = socket.gets
      break line if line.nil? || line[3] != "-"
    end
  end

  def read_smtp_lines(socket)
    [].tap do |lines|
      loop do
        line = socket.gets
        break if line.nil?
        lines << line.chomp
        break if line[3] != "-"
      end
    end
  end

  private
    def wait_until_listening(port, timeout: 10)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      begin
        TCPSocket.new("127.0.0.1", port).close
      rescue Errno::ECONNREFUSED
        raise if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.01
        retry
      end
    end
end
