require "socket"
require "net/smtp"

module SmtpTestHelper
  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def start_listener(listener_class, port_env, port)
    with_env(port_env => port, BIND_ADDRESS: "127.0.0.1") do
      listener_class.new.tap(&:start)
    end
  ensure
    wait_until_listening(port)
  end

  def stop_listener(listener)
    listener&.stop
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
