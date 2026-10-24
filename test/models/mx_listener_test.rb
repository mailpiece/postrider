require "test_helper"
require "net/smtp"

class MxListenerTest < ActiveSupport::TestCase
  include SmtpTestHelper

  self.use_transactional_tests = false

  setup do
    stub_env RELAY_HOSTNAME: "smtp-test.local"
    @domain = Current.account.domains.create!(name: "mx-listener-test.example", creator: users(:leo), dkim_status: :ok)
    @domain.mailboxes.create!(local_part: "everyone")
    @port = free_port
    @listener = start_listener(MxListener, "MX_PORT", @port)
  end

  teardown do
    stop_listener(@listener)
    Mailpiece.where(domain: @domain).delete_all
    InboundEmail.where(domain: @domain).delete_all
    Account::Cancellation.where(account: @domain.account).delete_all
    @domain.destroy
  end

  test "accepts mail for a registered domain and tenants the inbound email to the domain's account" do
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal @domain.account, inbound_email.account
    assert_equal "everyone@mx-listener-test.example", inbound_email.rcpt_to
    assert_equal "sender@example.com", inbound_email.mail_from
  end

  test "persists mailauth's SPF, DKIM, and DMARC verdicts on the inbound email" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "pass")

    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    perform_enqueued_jobs only: InboundEmail::ForwardJob

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal "pass", inbound_email.spf
    assert_equal "pass", inbound_email.dkim
    assert_equal "pass", inbound_email.dmarc
  end

  test "accepts and forwards mail nested too deep to parse" do
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: deeply_nested_raw)
    perform_enqueued_jobs only: InboundEmail::ForwardJob

    assert InboundEmail.order(:created_at).last.delivered?
  end

  test "rejects mail for an unregistered domain" do
    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "nobody@unregistered-mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
  end

  test "rejects mail for a domain whose account is cancelled" do
    @domain.account.create_cancellation!(initiated_by: users(:leo))

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
    assert_equal 0, InboundEmail.where(domain: @domain).count
  end

  test "rejects mail for a domain that is not verified" do
    @domain.update!(dkim_status: :missing)

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
    assert_equal 0, InboundEmail.where(domain: @domain).count
  end

  test "rejects mail for a domain whose receiving is turned off" do
    @domain.update!(receiving: false)

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
    assert_equal 0, InboundEmail.where(domain: @domain).count
  end

  test "rejects mail to an unregistered local part on an otherwise-registered domain" do
    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "nobody@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
  end

  test "accepts mail to postmaster with no explicit Mailbox created" do
    deliver(from: "sender@example.com", to: "postmaster@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    assert_equal "postmaster@mx-listener-test.example", InboundEmail.order(:created_at).last.rcpt_to
  end

  test "accepts mail to dmarc-reports with no explicit Mailbox created" do
    deliver(from: "sender@example.com", to: "dmarc-reports@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    assert_equal "dmarc-reports@mx-listener-test.example", InboundEmail.order(:created_at).last.rcpt_to
  end

  test "accepts a +suffix variant of a registered mailbox" do
    deliver(from: "sender@example.com", to: "everyone+something@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    assert_equal "everyone+something@mx-listener-test.example", InboundEmail.order(:created_at).last.rcpt_to
  end

  test "accepts mail to the account's configured bounce_address even though it's not a Mailbox" do
    @domain.account.setting.update!(bounce_address: "bounces@mx-listener-test.example")

    deliver(from: "sender@example.com", to: "bounces@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    assert_equal "bounces@mx-listener-test.example", InboundEmail.order(:created_at).last.rcpt_to
  end

  test "rejects mail to an unregistered local part when catch_all_policy is disabled" do
    @domain.update!(catch_all_policy: "disabled")

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "randomjunk@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
  end

  test "with catch_all_policy discard, an unregistered local part is accepted but recorded as discarded and never forwarded" do
    @domain.update!(catch_all_policy: "discard")

    assert_no_enqueued_jobs only: InboundEmail::ForwardJob do
      assert_difference -> { Event.count }, 0 do
        deliver(from: "sender@example.com", to: "randomjunk@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
      end
    end

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal "randomjunk@mx-listener-test.example", inbound_email.rcpt_to
    assert inbound_email.bounced?
    assert inbound_email.forwarded_at.present?
  end

  test "with catch_all_policy forward, an unregistered local part is accepted and forwarded just like a registered mailbox" do
    @domain.update!(catch_all_policy: "forward")

    assert_enqueued_jobs 1, only: InboundEmail::ForwardJob do
      deliver(from: "sender@example.com", to: "randomjunk@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal "randomjunk@mx-listener-test.example", inbound_email.rcpt_to
    assert inbound_email.pending?

    assert_difference -> { Event.count }, 1 do
      perform_enqueued_jobs only: InboundEmail::ForwardJob
    end

    assert inbound_email.reload.delivered?
    assert_equal "inbound_email_received", Event.last.action
  end

  test "rejects recipients past the MX_MAX_RECIPIENTS cap with a 452 without accepting the message" do
    with_env(MX_MAX_RECIPIENTS: 2) do
      error = assert_raises(Net::SMTPServerBusy) do
        deliver(from: "sender@example.com",
          to: %w[ everyone@mx-listener-test.example postmaster@mx-listener-test.example dmarc-reports@mx-listener-test.example ],
          raw: "Subject: Hi\r\n\r\nBody.\r\n")
      end

      assert_match "452", error.message
      assert_equal 0, inbound_email_count
    end
  end

  test "accepts a multi-recipient message up to the MX_MAX_RECIPIENTS cap" do
    with_env(MX_MAX_RECIPIENTS: 2) do
      deliver(from: "sender@example.com",
        to: %w[ everyone@mx-listener-test.example postmaster@mx-listener-test.example ],
        raw: "Subject: Hi\r\n\r\nBody.\r\n")

      assert_equal 2, inbound_email_count
    end
  end

  test "refuses mail at MAIL FROM with a 452 once stored mail reaches INBOUND_STORAGE_LIMIT" do
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    with_env(INBOUND_STORAGE_LIMIT: ActiveStorage::Blob.sum(:byte_size)) do
      error = assert_raises(Net::SMTPServerBusy) do
        deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nAgain.\r\n")
      end

      assert_match "452", error.message
      assert_equal 1, inbound_email_count
    end
  end

  test "accepts mail while stored mail is below INBOUND_STORAGE_LIMIT" do
    with_env(INBOUND_STORAGE_LIMIT: ActiveStorage::Blob.sum(:byte_size) + 1.megabyte) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

      assert_equal 1, inbound_email_count
    end
  end

  test "a message to several recipients is stored once and shared by every recipient's row" do
    blobs = ActiveStorage::Blob.uncached { ActiveStorage::Blob.count }

    deliver(from: "sender@example.com",
      to: %w[ everyone@mx-listener-test.example postmaster@mx-listener-test.example dmarc-reports@mx-listener-test.example ],
      raw: "Subject: Fanout\r\n\r\nBody.\r\n")

    emails = InboundEmail.uncached { InboundEmail.where(domain: @domain).to_a }
    assert_equal 3, emails.size
    assert_equal 1, emails.map { |email| email.raw_email.blob.id }.uniq.size
    assert_equal 1, ActiveStorage::Blob.uncached { ActiveStorage::Blob.count } - blobs
    assert_equal [ "Fanout" ], emails.map { |email| email[:subject] }.uniq
  end

  test "a remote retry of an already-accepted message is stored and forwarded only once" do
    raw = "Subject: Dup\r\n\r\nSame body.\r\n"

    assert_enqueued_jobs 1, only: InboundEmail::ForwardJob do
      2.times { deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: raw) }
    end

    assert_equal 1, inbound_email_count
  end

  test "two genuinely different messages to the same recipient are each accepted" do
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: One\r\n\r\nFirst.\r\n")
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Two\r\n\r\nSecond.\r\n")

    assert_equal 2, inbound_email_count
  end

  test "the same message to two different recipients is not mistaken for a duplicate" do
    raw = "Subject: Fanout\r\n\r\nSame body.\r\n"

    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: raw)
    deliver(from: "sender@example.com", to: "postmaster@mx-listener-test.example", raw: raw)

    assert_equal 2, inbound_email_count
  end

  test "detects a loop even when our own Received: stamp sits on a folded continuation line" do
    folded_stamps = Array.new(5) do |i|
      "Received: from relay#{i}.example (relay#{i}.example [10.0.0.#{i}])\r\n" \
        "\tby smtp-test.local with ESMTP; Wed, 01 Jan 2025 00:00:0#{i} +0000\r\n"
    end.join

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "#{folded_stamps}Subject: Loop\r\n\r\nBody.\r\n")
    end

    assert_match "554", error.message
  end

  test "reports a genuine handling exception in the envelope phase and asks the sender to retry" do
    Domain.stubs(:for_address).raises(RuntimeError, "boom")

    Rails.error.expects(:report).with(instance_of(RuntimeError), handled: false, source: "smtp").at_least_once
    Rails.error.stubs(:report).with(instance_of(RuntimeError), handled: false, source: "application.active_support")

    # Domain.accepts? goes through for_address, so this blows up at RCPT TO.
    # A 5xx here would permanently abandon mail we could still take tomorrow.
    error = assert_raises(Net::SMTPServerBusy) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "451", error.message
  end

  test "an unexpected error while accepting mail asks the sender to retry instead of dropping the message" do
    InboundEmail.stubs(:create!).raises(RuntimeError, "boom")

    error = assert_raises(Net::SMTPServerBusy) do
      deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "451", error.message
    assert_empty InboundEmail.where(domain: @domain)
  end

  test "fails to boot outside a local environment when no certificate is installed" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))

    assert_raises(Relay::Certificate::Missing) { MxListener.new }
  end

  test "stamps a client-supplied HELO into the Received header of the stored mail" do
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example",
      raw: "Subject: Hi\r\n\r\nBody.\r\n", helo: "friendly.sender.example")

    raw = InboundEmail.order(:created_at).last.raw
    assert_match(/\AReceived: from friendly\.sender\.example \(/, raw)
    assert_equal 1, raw[/\AReceived:.*?\r\n/m].to_s.count("\n")
  end

  test "neutralizes injection characters in the values stamped into the Received header" do
    mx = MxListener.allocate

    [
      "plain\r\nAuthentication-Results: smtp-test.local; dkim=pass",
      "a) (b [10.0.0.1]",
      "evil.example fake-token",
      "\t\x00control",
      "x" * 5000
    ].each do |hostile|
      session = session_with(helo: hostile, remote_ip: hostile)
      line = mx.send(:received_header, session)

      assert_equal 1, line.count("\n"), "extra line from #{hostile.inspect}"
      assert line.end_with?("\r\n")
      refute_includes line, "dkim=pass", "leaked injected token from #{hostile.inspect}"
      refute_includes line, "\x00"
    end
  end

  test "tolerates a few protocol errors but drops a connection that floods them" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      # Engine default: counts every protocol error, not just unrecognized commands.
      (MailSmtp::Server::MAX_EXCEPTIONS - 1).times do
        socket.write("GARBAGE\r\n")
        assert_match(/\A5\d\d /, socket.gets.to_s)
      end

      socket.write("GARBAGE\r\n")
      assert_match(/\A5\d\d /, socket.gets.to_s)
      assert_match(/\A421/, socket.gets.to_s)
      assert_nil socket.gets
    end
  end

  test "tolerates junk commands but drops a connection that floods them" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      MxListener::MAX_JUNK_COMMANDS.times do
        socket.write("NOOP\r\n")
        assert_match(/\A250/, socket.gets.to_s)
      end

      socket.write("NOOP\r\n")
      assert_match(/\A421/, socket.gets.to_s)
      assert_nil socket.gets
    end
  end

  test "drops a connection on its second junk command while stressed" do
    @listener.stubs(:stressed?).returns(true)

    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write("NOOP\r\n")
      assert_match(/\A250/, socket.gets.to_s)

      socket.write("NOOP\r\n")
      assert_match(/\A421/, socket.gets.to_s)
      assert_nil socket.gets
    end
  end

  test "refuses a message that streams past the inbound size limit and drops the connection" do
    with_inbound_size_limit(1.kilobyte) do |port|
      Socket.tcp("127.0.0.1", port) do |socket|
        socket.gets

        [ "HELO test.client.example", "MAIL FROM:<sender@example.com>", "RCPT TO:<everyone@mx-listener-test.example>", "DATA" ].each do |command|
          socket.write("#{command}\r\n")
          socket.gets
        end

        # No terminating "." — the size ceiling must end this. Two lines is barely over
        # so the 552 reply stays readable instead of racing a still-writing client.
        socket.write((("x" * 998) + "\r\n") * 2)

        assert_match(/\A552/, socket.gets.to_s)
        assert_equal 0, inbound_email_count
      end
    end
  end

  test "rejects an oversized SIZE declaration at MAIL FROM before any message data is sent" do
    with_inbound_size_limit(1.kilobyte) do |port|
      Socket.tcp("127.0.0.1", port) do |socket|
        socket.gets

        socket.write("HELO test.client.example\r\n")
        socket.gets

        socket.write("MAIL FROM:<sender@example.com> SIZE=#{2.kilobytes}\r\n")
        assert_match(/\A552/, socket.gets.to_s)
      end

      assert_equal 0, inbound_email_count
    end
  end

  test "keeps no recipient across STARTTLS, per RFC 3207" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      read_smtp_response(socket)
      socket.write "MAIL FROM:<pre@example.com>\r\n"
      socket.gets
      socket.write "RCPT TO:<everyone@mx-listener-test.example>\r\n"
      socket.gets

      # Out of sequence inside a transaction — an envelope can never straddle STARTTLS.
      socket.write "STARTTLS\r\n"
      assert_match(/\A503/, socket.gets.to_s)

      socket.write "RSET\r\n"
      socket.gets
      socket.write "STARTTLS\r\n"
      assert_match(/\A220/, socket.gets.to_s)

      ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
      ssl.connect

      # Clear-text state is gone after STARTTLS, including prior MAIL FROM.
      ssl.write "MAIL FROM:<post@example.com>\r\n"
      assert_match(/\A503/, ssl.gets.to_s)

      ssl.write "EHLO client.example\r\n"
      read_smtp_response(ssl)
      ssl.write "MAIL FROM:<post@example.com>\r\n"
      ssl.gets
      ssl.write "RCPT TO:<postmaster@mx-listener-test.example>\r\n"
      ssl.gets
      ssl.write "DATA\r\n"
      ssl.gets
      ssl.write "Subject: Hi\r\n\r\nBody.\r\n.\r\n"
      ssl.gets
      ssl.write "QUIT\r\n"
    end

    recipients = InboundEmail.uncached { InboundEmail.where(domain: @domain).pluck(:rcpt_to) }
    assert_equal [ "postmaster@mx-listener-test.example" ], recipients
  end

  test "refuses any RCPT TO parameter with a 555, since we advertise no extension that defines one" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets
      socket.write "MAIL FROM:<sender@example.com>\r\n"
      socket.gets

      socket.write "RCPT TO:<everyone@mx-listener-test.example> NOTIFY=NEVER\r\n"
      assert_match(/\A555/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  test "accepts the advertised MAIL FROM parameters whatever their case" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:<sender@example.com> size=512 body=7bit\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end
  end

  test "refuses a sender that is not a mailbox" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:<a b\"c@@x>\r\n"
      assert_match(/\A501/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  # Net::SMTP always brackets, so only a raw socket reaches this.
  test "accepts a bare path from a sender that omits the angle brackets" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:sender@example.com\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "RCPT TO:everyone@mx-listener-test.example\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "DATA\r\n"
      socket.gets
      socket.write "Subject: Hi\r\n\r\nBody.\r\n.\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal "sender@example.com", inbound_email.mail_from
    assert_equal "everyone@mx-listener-test.example", inbound_email.rcpt_to
  end

  test "reads ESMTP parameters after a bare path rather than swallowing them" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:sender@example.com BODY=8BITMIME\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      # RSET first, or the second MAIL FROM earns a 503 and never reaches the parameter.
      socket.write "RSET\r\n"
      socket.gets

      socket.write "MAIL FROM:sender@example.com RET=HDRS\r\n"
      assert_match(/\A555/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end
  end

  test "still refuses a bare path that is not a mailbox" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:a b\"c@@x\r\n"
      assert_match(/\A501/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  test "accepts the null reverse-path, which is how bounces arrive" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:<>\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end
  end

  # 550 rather than 501: RFC 5321 §4.5.1 makes it well-formed, only unroutable.
  test "refuses a domainless Postmaster recipient with a 550" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets
      socket.write "MAIL FROM:<sender@example.com>\r\n"
      socket.gets

      [ "Postmaster", "POSTMASTER", "postmaster" ].each do |recipient|
        socket.write "RCPT TO:<#{recipient}>\r\n"
        assert_match(/\A550/, socket.gets.to_s, "expected 550 for RCPT TO:<#{recipient}>")
      end

      socket.write "RCPT TO:<postmaster@mx-listener-test.example>\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  test "holds extracted addresses to the RFC 5321 mailbox grammar" do
    mx = MxListener.allocate

    assert mx.send(:mailbox?, "sender@example.com")
    assert mx.send(:mailbox?, "bounces+123.abc@mailer.example.com")
    assert mx.send(:mailbox?, "o'brien=news@single-label")

    assert_not mx.send(:mailbox?, "a b\"c@@x")
    assert_not mx.send(:mailbox?, ".leading@example.com")
    assert_not mx.send(:mailbox?, "double..dot@example.com")
    assert_not mx.send(:mailbox?, "user@-example.com")
    assert_not mx.send(:mailbox?, "user@example-.com")
    assert_not mx.send(:mailbox?, "user@example..com")
    assert_not mx.send(:mailbox?, "\"quoted string\"@example.com")
    assert_not mx.send(:mailbox?, "user@[127.0.0.1]")
    assert_not mx.send(:mailbox?, "user@")
    assert_not mx.send(:mailbox?, "@example.com")
  end

  test "enforces the RFC 5321 octet ceiling on the domain" do
    mx = MxListener.allocate
    longest_domain = Array.new(4) { "a" * 63 }.join(".")

    assert mx.send(:mailbox?, "user@#{longest_domain}")
    assert_not mx.send(:mailbox?, "user@#{longest_domain}.a")
  end

  # Gmail forwarding locals exceed RFC 5321's 64-octet ceiling; a 501 would permanently bounce their forwards.
  test "accepts a Gmail forwarding sender whose local part exceeds 64 octets" do
    gmail_forwarder = "jane.doe.forwarding.mailbox+caf_=everyone=mx-listener-test.example@gmail.com"
    assert_operator gmail_forwarder.split("@").first.bytesize, :>, 64

    deliver(from: gmail_forwarder, to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal gmail_forwarder, inbound_email.mail_from
    assert_equal "everyone@mx-listener-test.example", inbound_email.rcpt_to
    assert_includes inbound_email.raw_email.download, "Body."
  end

  test "refuses a pipelined command group, and never advertises PIPELINING" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      assert_not_includes read_smtp_lines(socket), "250-PIPELINING"

      socket.write "MAIL FROM:<sender@example.com>\r\n" \
        "RCPT TO:<everyone@mx-listener-test.example>\r\n"
      assert_match(/\A500/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  test "stores 8-bit message bytes exactly as the sender sent them" do
    body = "Caf\xC3\xA9 \xF0\x9F\x93\xAB in eight-bit octets".b

    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      read_smtp_lines(socket)
      socket.write "MAIL FROM:<sender@example.com> BODY=8BITMIME\r\n"
      socket.gets
      socket.write "RCPT TO:<everyone@mx-listener-test.example>\r\n"
      socket.gets
      socket.write "DATA\r\n"
      socket.gets
      socket.write "Subject: Hi\r\n\r\n#{body}\r\n.\r\n".b
      socket.gets
      socket.write "QUIT\r\n"
    end

    assert_includes InboundEmail.order(:created_at).last.raw_email.download.b, body
  end

  # Net::SMTP can't send a bare CR, so the body goes down a raw socket.
  test "refuses a body line carrying a bare CR" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      read_smtp_lines(socket)
      socket.write "MAIL FROM:<sender@example.com> BODY=8BITMIME\r\n"
      socket.gets
      socket.write "RCPT TO:<everyone@mx-listener-test.example>\r\n"
      socket.gets
      socket.write "DATA\r\n"
      socket.gets
      socket.write "Subject: Hi\r\n\r\nwith a bare\rCR inside\r\n.\r\n".b
      assert_match(/\A550/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  test "takes the BODY value it advertises and refuses a non-ASCII address or a wider one" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      socket.gets

      socket.write "HELO test.client.example\r\n"
      socket.gets

      socket.write "MAIL FROM:<\xE7\x94\xA8\xE6\x88\xB7@example.com>\r\n".b
      assert_match(/\A501/, socket.gets.to_s)

      socket.write "MAIL FROM:<sender@example.com> BODY=BINARYMIME\r\n"
      assert_match(/\A501/, socket.gets.to_s)

      # Confirms we refuse the BODY value, not BODY itself (submission rejects BODY entirely).
      socket.write "MAIL FROM:<sender@example.com> BODY=8BITMIME\r\n"
      assert_match(/\A250/, socket.gets.to_s)

      socket.write "QUIT\r\n"
    end

    assert_equal 0, inbound_email_count
  end

  test "advertises 8BITMIME in EHLO, since inbound mail is never relayed onward" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      assert_includes read_smtp_lines(socket), "250-8BITMIME"

      socket.write "QUIT\r\n"
    end
  end

  test "advertises the inbound size limit in EHLO, per RFC 1870" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      lines = read_smtp_lines(socket)

      assert_includes lines, "250-SIZE #{Relay.max_inbound_message_size}"

      socket.write "QUIT\r\n"
    end
  end

  test "preserves a legitimate IPv6 address literal HELO and rejects a malformed one" do
    mx = MxListener.allocate

    good = mx.send(:received_header, session_with(helo: "[IPv6:2001:db8::1]", remote_ip: "203.0.113.1"))
    assert_includes good, "from [IPv6:2001:db8::1] (unknown [203.0.113.1])"

    bad = mx.send(:received_header, session_with(helo: "", remote_ip: "203.0.113.1 x"))
    assert_includes bad, "from unknown (unknown [unknown])"
  end

  test "stamps unknown in the reverse-DNS slot without ever resolving one, so no stranger's DNS holds the connection" do
    DnsResolver.expects(:name).never

    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Hi\r\n\r\nBody.\r\n")

    raw = InboundEmail.order(:created_at).last.raw
    assert_match(/\AReceived: from test\.client\.example \(unknown \[127\.0\.0\.1\]\) by smtp-test\.local with ESMTP; /, raw)
  end

  test "stamps ESMTPS when the sender ran STARTTLS and ESMTP when it didn't" do
    with_starttls_smtp(@port) do |smtp|
      smtp.send_message("Subject: Encrypted\r\n\r\nBody.\r\n", "sender@example.com", "everyone@mx-listener-test.example")
    end

    assert_match(/by smtp-test\.local with ESMTPS; /, last_inbound_email_raw)

    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Plain\r\n\r\nBody.\r\n")

    assert_match(/by smtp-test\.local with ESMTP; /, last_inbound_email_raw)
  end

  test "keeps serving after an accept fails" do
    fail_the_next_accept

    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: One\r\n\r\nBody.\r\n")
    deliver(from: "sender@example.com", to: "everyone@mx-listener-test.example", raw: "Subject: Two\r\n\r\nBody.\r\n")

    assert_not @listener.stopped?
    assert_equal 2, inbound_email_count
  end

  private
    # Acceptor is already blocked in accept; first delivery lands, then the next accept fails.
    def fail_the_next_accept
      tcp_server = @listener.instance_variable_get(:@tcp_servers).first

      def tcp_server.accept
        if @accept_failed
          super
        else
          @accept_failed = true
          raise Errno::ECONNABORTED
        end
      end
    end

    def deliver(from:, to:, raw:, helo: "test.client.example")
      mx_deliver(port: @port, from: from, to: to, raw: raw, helo: helo)
    end

    # max_message_size is read at construct time, so a smaller ceiling needs its own listener.
    def with_inbound_size_limit(bytes)
      with_env(INBOUND_MAX_MESSAGE_SIZE: bytes) do
        port = free_port
        listener = start_listener(MxListener, "MX_PORT", port)

        begin
          yield port
        ensure
          stop_listener(listener)
        end
      end
    end

    def session_with(helo: nil, remote_ip: nil)
      session = SmtpSession.new
      session.helo = helo
      session.remote_ip = remote_ip
      session
    end

    def inbound_email_count
      InboundEmail.uncached { InboundEmail.where(domain: @domain).count }
    end

    def last_inbound_email_raw
      InboundEmail.uncached { InboundEmail.order(:created_at).last.raw }
    end
end
