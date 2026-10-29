require "test_helper"

class Mailbox::SuspendingTest < ActiveSupport::TestCase
  setup do
    @mailbox = mailboxes(:forwarding)
    @message = domains(:example).messages.create!(mail_from: "jane@remote.example", raw: "Subject: Hi\r\n\r\nBody", origin: :forwarded)
    @delivery = @message.deliveries.create!(rcpt_to: @mailbox.forward_to)
    Delivery.any_instance.stubs(:destination_hosts).returns([])
    MtaStsPolicy.stubs(:lookup).returns(MtaSts::Result.new(status: "none"))
  end

  test "a permanent bounce of a forward suspends forwarding to the dead destination" do
    stub_smtp(:hard_fail, "550", "no such user")

    @delivery.deliver

    assert @delivery.reload.bounced?
    assert_nil @mailbox.reload.forward_confirmed_at
  end

  test "a permanent bounce of an ordinary message leaves forwarding alone" do
    @message.update!(origin: :submitted)
    stub_smtp(:hard_fail, "550", "no such user")

    @delivery.deliver

    assert @mailbox.reload.forward_confirmed_at.present?
  end

  test "a deferral does not suspend forwarding" do
    stub_smtp(:soft_fail, "451", "greylisted, try later")

    assert_raises(RuntimeError) { @delivery.deliver }

    assert @mailbox.reload.forward_confirmed_at.present?
  end

  test "running out of retries on a full destination suspends forwarding" do
    @delivery.attempts.create!(code: "452", output: "452 4.2.2 Mailbox full", mx_host: "mx.example.com")

    @delivery.exhaust

    assert_nil @mailbox.reload.forward_confirmed_at
  end

  test "an async DSN reporting the destination invalid suspends forwarding" do
    @delivery.update!(status: :delivered)

    @delivery.record_async_bounce(dsn_raw: failing_dsn)

    assert_nil @mailbox.reload.forward_confirmed_at
  end

  test "an async DSN for an ordinary message leaves forwarding alone" do
    @message.update!(origin: :submitted)
    @delivery.update!(status: :delivered)

    @delivery.record_async_bounce(dsn_raw: failing_dsn)

    assert @mailbox.reload.forward_confirmed_at.present?
  end

  private
    def stub_smtp(status, code, output)
      SmtpDelivery.any_instance.stubs(:deliver).returns(
        SmtpDelivery::Result.new(status, code, output, "mx.example.com", "transcript")
      )
    end

    def failing_dsn
      "From: MAILER-DAEMON@mx.example.com\r\nSubject: Undelivered Mail Returned to Sender\r\n" \
        "Content-Type: multipart/report; report-type=delivery-status; boundary=\"BB\"\r\n\r\n" \
        "--BB\r\nContent-Type: text/plain\r\n\r\nDelivery to the recipient failed.\r\n\r\n" \
        "--BB\r\nContent-Type: message/delivery-status\r\n\r\nReporting-MTA: dns; mx.example.com\r\n\r\n" \
        "Final-Recipient: rfc822; #{@mailbox.forward_to}\r\nAction: failed\r\nStatus: 5.1.1\r\n\r\n--BB--\r\n"
    end
end
