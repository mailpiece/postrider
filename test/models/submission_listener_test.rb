require "test_helper"
require "net/smtp"
require "base64"

class SubmissionListenerTest < ActiveSupport::TestCase
  include SmtpTestHelper
  include CertificateTestHelper

  self.use_transactional_tests = false

  setup do
    stub_env RELAY_HOSTNAME: "smtp-test.local"
    @test_started_at = Time.current
    @port = free_port
    @listener = start_listener(SubmissionListener, "SUBMISSION_PORT", @port)
  end

  teardown do
    stop_listener(@listener)
    account = accounts(:davids_account)
    Event.where(account: account).where("created_at >= ?", @test_started_at).delete_all
    Mailpiece.where(account: account).where("created_at >= ?", @test_started_at).delete_all
    Delivery.where(account: account).where("created_at >= ?", @test_started_at).delete_all
    Message.where(account: account).where("created_at >= ?", @test_started_at).delete_all
    IdempotentRequest.where("created_at >= ?", @test_started_at).delete_all
    SendingToken.where(account: account).where("created_at >= ?", @test_started_at).delete_all
    Account::Cancellation.where(account: account).where("created_at >= ?", @test_started_at).delete_all
  end

  test "does not advertise 8BITMIME, since submitted mail is relayed onward and we never downgrade it" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)

      socket.write "EHLO client.example\r\n"
      capabilities = read_smtp_lines(socket)

      assert_not_includes capabilities, "250-8BITMIME"
      assert_includes capabilities, "250-STARTTLS"

      socket.write "QUIT\r\n"
    end
  end

  test "authenticates with a sending token and tenants the outbound message to its account" do
    deliver(from: "sender@example.com", to: "recipient@example.com")

    message = Message.order(:created_at).last
    assert_equal accounts(:davids_account), message.account
    assert_equal "recipient@example.com", message.deliveries.sole.rcpt_to
    assert_equal accounts(:davids_account), message.deliveries.sole.account
  end

  test "stamps a Received: by header without the client's HELO or origin IP" do
    deliver(from: "sender@example.com", to: "recipient@example.com")

    raw = Message.order(:created_at).last.raw
    assert_match(/\AReceived: by smtp-test\.local with ESMTPSA; /, raw)
    assert_no_match(/Received: from/, raw)
    assert_no_match(/127\.0\.0\.1/, raw)
  end

  test "submitting identical message bytes twice creates a single outbound message and both submissions succeed" do
    message = "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    first = deliver(from: "sender@example.com", to: "recipient@example.com", message: message)
    second = deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    assert_equal "250", first.status
    assert_equal "250", second.status
    assert_equal 1, submitted_messages.count
    assert_equal 1, submitted_messages.sole.deliveries.count
  end

  test "submitting identical bytes to different envelope recipients creates a message for each" do
    message = "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "one@example.com", message: message)
    deliver(from: "sender@example.com", to: "two@example.com", message: message)

    assert_equal 2, submitted_messages.count
  end

  test "submitting two different messages creates two outbound messages" do
    deliver(from: "sender@example.com", to: "recipient@example.com",
      message: "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: One\r\n\r\nFirst.\r\n")
    deliver(from: "sender@example.com", to: "recipient@example.com",
      message: "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Two\r\n\r\nSecond.\r\n")

    assert_equal 2, submitted_messages.count
  end

  test "the SMTP username is ignored — only the token authenticates" do
    deliver(from: "sender@example.com", to: "recipient@example.com", username: "anything-at-all")

    assert_equal 1, submitted_messages.count
  end

  test "authenticates a one-line AUTH PLAIN whose credential encodes to + and /" do
    # These bytes encode to base64 "+" and "/", covering both non-alphanumeric characters.
    username = "us".b + [ 0xFB, 0xEF, 0xBE, 0xFF, 0xFF, 0xFF ].pack("C*")
    credential = Base64.strict_encode64("\0".b + username + "\0".b + DomainTestHelper::SENDING_TOKEN)
    assert_includes credential, "+"
    assert_includes credential, "/"

    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)
      socket.write "EHLO client.example\r\n"
      read_smtp_response(socket)
      socket.write "STARTTLS\r\n"
      socket.gets

      ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
      ssl.connect
      ssl.write "EHLO client.example\r\n"
      read_smtp_response(ssl)

      ssl.write "AUTH PLAIN #{credential}\r\n"
      assert_match(/\A235/, ssl.gets.to_s)
    end
  end

  test "authenticates with AUTH LOGIN" do
    deliver(from: "sender@example.com", to: "recipient@example.com", auth_type: :login)

    assert_equal 1, submitted_messages.count
    assert_equal accounts(:davids_account), submitted_messages.sole.account
  end

  test "rejects an invalid token presented over AUTH LOGIN" do
    error = assert_raises(Net::SMTPAuthenticationError) do
      with_starttls_smtp(@port) do |smtp|
        smtp.authenticate(SendingToken::SMTP_USERNAME, "wrong-token", :login)
      end
    end

    assert_match "535", error.message
  end

  test "accepts an AUTH LOGIN that supplies the username as an initial response" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)
      socket.write "EHLO client.example\r\n"
      read_smtp_response(socket)
      socket.write "STARTTLS\r\n"
      socket.gets

      ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
      ssl.connect
      ssl.write "EHLO client.example\r\n"
      read_smtp_response(ssl)

      ssl.write "AUTH LOGIN #{Base64.strict_encode64(SendingToken::SMTP_USERNAME)}\r\n"
      assert_match(/\A334 /, ssl.gets.to_s)
      ssl.write "#{Base64.strict_encode64(DomainTestHelper::SENDING_TOKEN)}\r\n"
      assert_match(/\A235/, ssl.gets.to_s)
    end
  end

  test "advertises AUTH PLAIN LOGIN and still refuses an unknown mechanism with 504" do
    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)
      socket.write "EHLO client.example\r\n"
      read_smtp_response(socket)
      socket.write "STARTTLS\r\n"
      socket.gets

      ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
      ssl.connect
      ssl.write "EHLO client.example\r\n"
      capabilities = read_smtp_lines(ssl)
      assert_includes capabilities, "250-AUTH PLAIN LOGIN"

      ssl.write "AUTH CRAM-MD5\r\n"
      assert_match(/\A504/, ssl.gets.to_s)

      ssl.write "AUTH PLAIN #{Base64.strict_encode64("\0#{SendingToken::SMTP_USERNAME}\0#{DomainTestHelper::SENDING_TOKEN}")}\r\n"
      assert_match(/\A235/, ssl.gets.to_s)
    end
  end

  test "redacts the credential from the debug wire log in every auth-value state" do
    listener = SubmissionListener.allocate
    session = SmtpSession.new

    session.phase = :ready
    assert_equal "EHLO client.example", listener.send(:loggable_command, session, "EHLO client.example")
    assert_equal "AUTH LOGIN", listener.send(:loggable_command, session, "AUTH LOGIN")
    assert_equal "AUTH PLAIN [redacted]", listener.send(:loggable_command, session, "AUTH PLAIN AHVzZXIAcGFzcw==")
    assert_equal "AUTH LOGIN [redacted]", listener.send(:loggable_command, session, "AUTH LOGIN dXNlcg==")

    %i[ auth_plain auth_login_user auth_login_pass ].each do |phase|
      session.phase = phase
      assert_equal "[redacted credential]", listener.send(:loggable_command, session, "AHVzZXIAcGFzcw==")
    end
  end

  test "does not log a pipelined AUTH credential verbatim" do
    logged = []
    @listener.define_singleton_method(:log) do |_session, _severity, msg, err: nil|
      logged << msg.to_s
    end

    credential = Base64.strict_encode64("\0#{SendingToken::SMTP_USERNAME}\0#{DomainTestHelper::SENDING_TOKEN}")

    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)
      socket.write "EHLO client.example\r\n"
      read_smtp_response(socket)
      socket.write "STARTTLS\r\n"
      socket.gets

      ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
      ssl.connect
      ssl.write "EHLO client.example\r\n"
      read_smtp_lines(ssl)

      # Command and credential in one write: the continuation must be dropped, not logged.
      ssl.write "AUTH PLAIN\r\n#{credential}\r\n"
      assert_match(/\A500/, ssl.gets.to_s)

      ssl.write "QUIT\r\n"
      ssl.gets
    end

    # After close so the connection thread is done logging.
    assert logged.any? { |msg| msg.include?("PipeliningNotSupported") }, "expected the pipelined command to be rejected"
    assert_not logged.any? { |msg| msg.include?(credential) }, "the pipelined credential leaked into the log"
    assert_not logged.any? { |msg| msg.include?(DomainTestHelper::SENDING_TOKEN) }, "the token leaked into the log"
  end

  test "accepts a message containing a blocked phrase like any other, and sends it nowhere" do
    domains(:example).update!(blocked_phrases: "free money")
    response = nil

    assert_no_enqueued_jobs only: Delivery::DeliverJob do
      response = deliver(from: "sender@example.com", to: "recipient@example.com",
        message: "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Free, money!\r\n\r\nBody.\r\n")
    end

    assert_equal "250", response.status
    assert submitted_messages.sole.deliveries.sole.withheld?
  end

  test "rejects a submission from a cancelled account" do
    Current.account.create_cancellation!(initiated_by: users(:leo))

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "recipient@example.com")
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "rejects an invalid token" do
    error = assert_raises(Net::SMTPAuthenticationError) do
      with_starttls_smtp(@port) do |smtp|
        smtp.authenticate(SendingToken::SMTP_USERNAME, "wrong-token", :plain)
      end
    end

    assert_match "535", error.message
  end

  test "refuses a token used from outside its domain's allowed IPs and records the refusal" do
    domains(:example).update!(allowed_ips: "203.0.113.0/24")

    with_memory_cache do
      assert_no_changes -> { sending_tokens(:example).reload.last_used_at } do
        error = assert_raises(Net::SMTPAuthenticationError) do
          deliver(from: "sender@example.com", to: "recipient@example.com")
        end

        assert_match "535 5.7.1", error.message
      end
    end

    assert_equal 0, submitted_messages.count
    event = domains(:example).events.find_by!(action: "sending_token_refused")
    assert_equal({ "token_name" => "Example sending token", "ip" => "127.0.0.1" }, event.particulars)
  ensure
    domains(:example).update_column :allowed_ips, nil
  end

  test "accepts a token used from inside its domain's allowed IPs" do
    domains(:example).update!(allowed_ips: "127.0.0.1")

    deliver(from: "sender@example.com", to: "recipient@example.com")

    assert_equal 1, submitted_messages.count
  ensure
    domains(:example).update_column :allowed_ips, nil
  end

  test "a sending token is marked as used after a successful submission, not at AUTH or on a replay" do
    sending_tokens(:example).update_column :last_used_at, nil
    message = "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    with_starttls_smtp(@port) do |smtp|
      smtp.authenticate(SendingToken::SMTP_USERNAME, DomainTestHelper::SENDING_TOKEN, :plain)
    end
    assert_nil sending_tokens(:example).reload.last_used_at

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)
    used_at = sending_tokens(:example).reload.last_used_at
    assert used_at.present?

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)
    assert_equal used_at, sending_tokens(:example).reload.last_used_at
  end

  test "a domain-scoped token may send as its own domain" do
    scoped = domains(:private).sending_tokens.create!(name: "Scoped")

    deliver(token: scoped.token, from: "news@private.example", to: "recipient@example.com")

    assert_equal "news@private.example", Message.order(:created_at).last.mail_from
  end

  test "a domain-scoped token is rejected sending as another domain" do
    scoped = domains(:private).sending_tokens.create!(name: "Scoped")

    error = assert_raises(Net::SMTPFatalError) do
      deliver(token: scoped.token, from: "news@other.example", to: "recipient@example.com")
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "a domain-scoped token is rejected sending as its own domain when it isn't DKIM-verified yet" do
    scoped = domains(:unverified).sending_tokens.create!(name: "Scoped")

    error = assert_raises(Net::SMTPFatalError) do
      deliver(token: scoped.token, from: "news@unverified.example", to: "recipient@example.com")
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "rejects MAIL FROM for a domain whose sending is turned off" do
    domains(:example).update_column :sending, false

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "recipient@example.com")
    end

    assert_match "550 5.7.1", error.message
    assert_equal 0, submitted_messages.count
  ensure
    domains(:example).update_column :sending, true
  end

  test "rejects a visible From header the token isn't authorized for, even when the envelope sender is authorized" do
    spoofed = "From: ceo@victim.example\r\nTo: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "recipient@example.com", message: spoofed)
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "rejects a Sender header the token isn't authorized for, even when From and the envelope sender are authorized" do
    spoofed = "From: sender@example.com\r\nSender: ceo@victim.example\r\n" \
      "To: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "recipient@example.com", message: spoofed)
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "accepts a Sender header naming another address on the token's own domain" do
    message = "From: sender@example.com\r\nSender: assistant@example.com\r\n" \
      "To: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    assert_match "Sender: assistant@example.com", Message.order(:created_at).last.raw
  end

  test "accepts a resent chain naming addresses on other domains" do
    message = "Resent-From: carol@example.net\r\nResent-From: bob@example.org\r\n" \
      "From: sender@example.com\r\nTo: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    assert_match "Resent-From: bob@example.org", Message.order(:created_at).last.raw
  end

  test "accepts a Reply-To header pointing at an unrelated domain" do
    message = "From: sender@example.com\r\nReply-To: help@unrelated.example\r\n" \
      "To: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    assert_match "Reply-To: help@unrelated.example", Message.order(:created_at).last.raw
  end

  test "strips a client-supplied Authentication-Results header from the relayed bytes" do
    message = "From: sender@example.com\r\nTo: recipient@example.com\r\n" \
      "Authentication-Results: mx.example; dkim=pass header.d=victim.example\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    assert_no_match(/authentication-results/i, Message.order(:created_at).last.raw)
  end

  test "replaces a Message-ID whose host leaks the sending machine with one at the sending domain" do
    message = "From: sender@example.com\r\nTo: recipient@example.com\r\n" \
      "Message-ID: <leak@app-1.internal.example.mail>\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    raw = Message.order(:created_at).last.raw
    assert_no_match(/internal\.example/, raw)
    assert_match(/Message-ID: <[^@>]+@example\.com>/, raw)
  end

  test "keeps a Message-ID the sender already set at their own sending domain" do
    message = "From: sender@example.com\r\nTo: recipient@example.com\r\n" \
      "Message-ID: <keep-me@example.com>\r\nSubject: Hi\r\n\r\nBody.\r\n"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    assert_match "Message-ID: <keep-me@example.com>", Message.order(:created_at).last.raw
  end

  test "rejects a submission missing a From header" do
    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "recipient@example.com",
        message: "To: recipient@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "rejects a submission missing a To header" do
    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "recipient@example.com",
        message: "From: sender@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "550", error.message
    assert_equal 0, submitted_messages.count
  end

  test "extracts a comma-separated X-PostRider-Tags header into tags, without leaking the header" do
    deliver(from: "sender@example.com", to: "recipient@example.com",
      message: "From: sender@example.com\r\nTo: recipient@example.com\r\nX-PostRider-Tags: tag one, tag two\r\nSubject: Hi\r\n\r\nBody.\r\n")

    message = Message.order(:created_at).last
    assert_equal [ "tag one", "tag two" ], message.tags
    assert_no_match(/x-postrider-tags/i, message.raw)
  end

  test "extracts a single X-PostRider-Tags value into tags" do
    deliver(from: "sender@example.com", to: "recipient@example.com",
      message: "From: sender@example.com\r\nTo: recipient@example.com\r\nX-PostRider-Tags: solo\r\nSubject: Hi\r\n\r\nBody.\r\n")

    assert_equal [ "solo" ], Message.order(:created_at).last.tags
  end

  test "rejects an X-PostRider-Tags header carrying more than the max tags" do
    tags = (1..Message::MAX_TAGS + 1).map { |i| "tag#{i}" }.join(",")

    error = assert_no_difference -> { Message.count } do
      assert_raises(Net::SMTPFatalError) do
        deliver(from: "sender@example.com", to: "recipient@example.com",
          message: "From: sender@example.com\r\nTo: recipient@example.com\r\nX-PostRider-Tags: #{tags}\r\nSubject: Hi\r\n\r\nBody.\r\n")
      end
    end

    assert_match "550", error.message
  end

  test "promotes X-List-Unsubscribe to a List-Unsubscribe header, adding List-Unsubscribe-Post for an https URI" do
    deliver(from: "sender@example.com", to: "recipient@example.com",
      message: "From: sender@example.com\r\nTo: recipient@example.com\r\nX-List-Unsubscribe: <https://example.com/unsub>\r\nSubject: Hi\r\n\r\nBody.\r\n")

    raw = Message.order(:created_at).last.raw
    assert_match "List-Unsubscribe: <https://example.com/unsub>", raw
    assert_match "List-Unsubscribe-Post: List-Unsubscribe=One-Click", raw
    assert_no_match(/x-list-unsubscribe/i, raw)
  end

  test "does not add List-Unsubscribe-Post for a mailto-only X-List-Unsubscribe value" do
    deliver(from: "sender@example.com", to: "recipient@example.com",
      message: "From: sender@example.com\r\nTo: recipient@example.com\r\nX-List-Unsubscribe: <mailto:list@example.com?subject=unsubscribe>\r\nSubject: Hi\r\n\r\nBody.\r\n")

    raw = Message.order(:created_at).last.raw
    assert_match "List-Unsubscribe: <mailto:list@example.com?subject=unsubscribe>", raw
    assert_no_match(/List-Unsubscribe-Post/, raw)
  end

  test "leaves a multipart body with an attachment byte-for-byte untouched, even while directive headers are rewritten" do
    boundary = "BOUNDARY123"
    body = [
      "--#{boundary}",
      "Content-Type: text/plain",
      "",
      "Hello there.",
      "--#{boundary}",
      "Content-Type: application/octet-stream",
      "Content-Transfer-Encoding: base64",
      "Content-Disposition: attachment; filename=\"file.bin\"",
      "",
      Base64.strict_encode64("not really binary but pretend").scan(/.{1,76}/).join("\r\n"),
      "--#{boundary}--"
    ].join("\r\n")

    message = "From: sender@example.com\r\nTo: recipient@example.com\r\n" \
      "X-PostRider-Tags: attach test\r\nX-List-Unsubscribe: <https://example.com/unsub>\r\n" \
      "Content-Type: multipart/mixed; boundary=\"#{boundary}\"\r\nSubject: Hi\r\n\r\n#{body}"

    deliver(from: "sender@example.com", to: "recipient@example.com", message: message)

    stored = Message.order(:created_at).last
    # Trailing CRLF terminates the last body line; only <CRLF>.<CRLF> was transfer framing.
    assert_equal "#{body}\r\n", stored.raw.split("\r\n\r\n", 2).last
    assert_equal [ "attach test" ], stored.tags
  end

  test "refuses a submission with more than MAX_RECIPIENTS envelope recipients" do
    max = Message::Submitting::MAX_RECIPIENTS
    recipients = Array.new(max + 1) { |n| "r#{n}@example.com" }

    error = assert_raises(Net::SMTPServerBusy) do
      deliver(from: "sender@example.com", to: recipients,
        message: "From: sender@example.com\r\nTo: list@example.com\r\nSubject: Hi\r\n\r\nBody.\r\n")
    end

    assert_match "452", error.message
    assert_equal 0, submitted_messages.count
  end

  test "refuses submission with a temporary 452 when the account is over its rate limit" do
    SubmissionRateLimiter.stubs(:exceeded?).returns(true)

    error = assert_raises(Net::SMTPServerBusy) do
      deliver(from: "sender@example.com", to: "recipient@example.com")
    end

    assert_match "452", error.message
    assert_equal 0, submitted_messages.count
  end

  test "reports a genuine handling exception during AUTH to the error reporter" do
    SendingToken.stubs(:authenticate).raises(RuntimeError, "boom")

    Rails.error.expects(:report).with(instance_of(RuntimeError), handled: false, source: "smtp").at_least_once

    assert_raises(Net::SMTPAuthenticationError) do
      with_starttls_smtp(@port) { |smtp| smtp.authenticate(DomainTestHelper::SENDING_TOKEN, "irrelevant", :plain) }
    end
  end

  test "an unexpected error while accepting a submission asks the sender to retry instead of dropping the message" do
    Message.any_instance.stubs(:save!).raises(RuntimeError, "boom")

    error = assert_raises(Net::SMTPServerBusy) do
      deliver(from: "sender@example.com", to: "recipient@example.com")
    end

    assert_match "451", error.message
    assert_empty Message.where(account: accounts(:davids_account)).where("created_at >= ?", @test_started_at)
  end

  test "refuses a BODY declaration with a 501, since submission never advertises 8BITMIME" do
    with_authenticated_session do |ssl|
      # 501 not 555: BODY is known; leaving 8BITMIME off is what refuses it.
      ssl.write "MAIL FROM:<sender@example.com> BODY=8BITMIME\r\n"
      assert_match(/\A501/, ssl.gets.to_s)
    end

    assert_equal 0, submitted_messages.count
  end

  test "refuses a RCPT TO parameter with a 555 and a malformed recipient with a 501" do
    with_authenticated_session do |ssl|
      ssl.write "MAIL FROM:<sender@example.com>\r\n"
      assert_match(/\A250/, ssl.gets.to_s)

      ssl.write "RCPT TO:<recipient@example.com> NOTIFY=NEVER\r\n"
      assert_match(/\A555/, ssl.gets.to_s)

      ssl.write "RCPT TO:<not an address@@x>\r\n"
      assert_match(/\A501/, ssl.gets.to_s)
    end

    assert_equal 0, submitted_messages.count
  end

  # Unlike MX, submission clients are ours — bare paths are refused.
  test "refuses a bare path that omits the angle brackets" do
    with_authenticated_session do |ssl|
      ssl.write "MAIL FROM:sender@example.com\r\n"
      assert_match(/\A501/, ssl.gets.to_s)
    end

    assert_equal 0, submitted_messages.count
  end

  # 501, not MX's 550: submission has no domain to route Postmaster by.
  test "refuses a domainless Postmaster recipient with a 501" do
    with_authenticated_session do |ssl|
      ssl.write "MAIL FROM:<sender@example.com>\r\n"
      assert_match(/\A250/, ssl.gets.to_s)

      ssl.write "RCPT TO:<Postmaster>\r\n"
      assert_match(/\A501/, ssl.gets.to_s)
    end

    assert_equal 0, submitted_messages.count
  end

  test "greets with SUBMISSION_HOSTNAME, not RELAY_HOSTNAME, when they differ" do
    with_env(SUBMISSION_HOSTNAME: "submission-test.local") do
      Socket.tcp("127.0.0.1", @port) do |socket|
        greeting = socket.gets
        assert_match(/submission-test\.local/, greeting)
        assert_no_match(/smtp-test\.local/, greeting)
      end
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

  test "drops a connection that floods failed authentication attempts" do
    bad_credentials = Base64.strict_encode64("\0#{SendingToken::SMTP_USERNAME}\0wrong-token")

    Socket.tcp("127.0.0.1", @port) do |socket|
      read_smtp_response(socket)
      socket.write "EHLO client.example\r\n"
      read_smtp_response(socket)
      socket.write "STARTTLS\r\n"
      socket.gets

      ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
      ssl.connect
      ssl.write "EHLO client.example\r\n"
      read_smtp_response(ssl)

      # Engine answers the last failure before closing: 535, then 421.
      (MailSmtp::Server::MAX_AUTH_FAILURES - 1).times do
        ssl.write "AUTH PLAIN\r\n"
        ssl.gets
        ssl.write "#{bad_credentials}\r\n"
        assert_match(/\A535/, ssl.gets.to_s)
      end

      ssl.write "AUTH PLAIN\r\n"
      ssl.gets
      ssl.write "#{bad_credentials}\r\n"
      assert_match(/\A535/, ssl.gets.to_s)
      assert_match(/\A421/, ssl.gets.to_s)
      assert_nil ssl.gets
    end
  end

  test "serves a self-signed certificate until one is issued" do
    assert_equal "/CN=#{Relay::TlsContext::SELF_SIGNED_CN}", starttls_peer_cert.subject.to_s
  end

  test "reload_tls serves a newly issued certificate to new connections without a restart" do
    assert_no_match(/renewed\.example/, starttls_peer_cert.subject.to_s)

    Relay::Certificate.instance.update! pem: certificate_pem(cn: "renewed.example")
    @listener.reload_tls

    assert_match(/renewed\.example/, starttls_peer_cert.subject.to_s)
  ensure
    Relay::Certificate.delete_all
  end

  private
    def with_authenticated_session
      Socket.tcp("127.0.0.1", @port) do |socket|
        read_smtp_response(socket)
        socket.write "EHLO client.example\r\n"
        read_smtp_response(socket)
        socket.write "STARTTLS\r\n"
        socket.gets

        ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
        ssl.connect
        ssl.write "EHLO client.example\r\n"
        read_smtp_response(ssl)

        ssl.write "AUTH PLAIN #{Base64.strict_encode64("\0#{SendingToken::SMTP_USERNAME}\0#{DomainTestHelper::SENDING_TOKEN}")}\r\n"
        assert_match(/\A235/, ssl.gets.to_s)

        yield ssl
      end
    end

    def starttls_peer_cert
      Socket.tcp("127.0.0.1", @port) do |socket|
        read_smtp_response socket
        socket.write "EHLO peer-cert-probe.example\r\n"
        read_smtp_response socket
        socket.write "STARTTLS\r\n"
        read_smtp_response socket

        ssl = OpenSSL::SSL::SSLSocket.new(socket, insecure_tls_context)
        ssl.connect
        ssl.peer_cert
      end
    end

    def deliver(from:, to:, token: DomainTestHelper::SENDING_TOKEN, username: SendingToken::SMTP_USERNAME, message: nil, auth_type: :plain)
      submission_deliver(port: @port, token: token, from: from, to: to, username: username, message: message, auth_type: auth_type)
    end

    def submitted_messages
      Message.where(created_at: @test_started_at..)
    end

    def with_memory_cache
      previous_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      yield
    ensure
      Rails.cache = previous_cache
    end
end
