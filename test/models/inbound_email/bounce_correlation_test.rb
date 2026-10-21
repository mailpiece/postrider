require "test_helper"
require "net/smtp"

class InboundEmail::BounceCorrelationTest < ActiveSupport::TestCase
  include SmtpTestHelper

  self.use_transactional_tests = false

  setup do
    stub_env RELAY_HOSTNAME: "smtp-test.local"
    @domain = Current.account.domains.create!(name: "bounce-corr-test.example", creator: users(:leo),
      dkim_status: :ok)
    @return_path = "bounces+abc123.deadbeef01@mailer.bounce-corr-test.example"
    @port = free_port
    @listener = start_listener(MxListener, "MX_PORT", @port)
  end

  teardown do
    stop_listener(@listener)
    Mailpiece.where(domain: @domain).delete_all
    InboundEmail.where(domain: @domain).delete_all
    @domain.destroy
  end

  test "accepts a return-path DSN, tenants the audit record to the sending account, and enqueues correlation" do
    Delivery::ReturnPath.stubs(:address?).with(@return_path).returns(true)
    Delivery::ReturnPath.stubs(:bounce_domain).with(@return_path).returns(@domain)

    assert_enqueued_jobs 1, only: InboundEmail::BounceCorrelationJob do
      deliver(from: "", to: @return_path, raw: dsn_raw)
    end

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal @domain.account, inbound_email.account
    assert_equal @return_path, inbound_email.rcpt_to
  end

  test "accepts a relay-owned default bounce, tenants it to the delivery's account, and enqueues correlation" do
    message = Message.create!(
      domain: @domain, mail_from: "sender@bounce-corr-test.example", raw: "Subject: Hi\r\n\r\nBody")
    delivery = message.deliveries.create!(rcpt_to: "recipient@example.com")
    address = Delivery::ReturnPath.verp.address_for(delivery.id, domain: "smtp-test.local")

    assert_enqueued_jobs 1, only: InboundEmail::BounceCorrelationJob do
      deliver(from: "", to: address, raw: dsn_raw)
    end

    inbound_email = InboundEmail.order(:created_at).last
    assert_equal @domain.account, inbound_email.account
    assert_equal address, inbound_email.rcpt_to
  ensure
    delivery&.destroy
    message&.destroy
  end

  test "still rejects an address that is neither a registered domain nor a return path" do
    Delivery::ReturnPath.stubs(:address?).returns(false)

    error = assert_raises(Net::SMTPFatalError) do
      deliver(from: "sender@example.com", to: "nobody@unregistered-bounce-corr.example", raw: dsn_raw)
    end

    assert_match "550", error.message
  end

  test "correlate_bounce records the async bounce against the matched delivery and marks the audit delivered" do
    email = InboundEmail.create!(domain: @domain, mail_from: "", rcpt_to: @return_path, raw: dsn_raw)
    delivery = mock("delivery")
    delivery.expects(:record_async_bounce).with(dsn_raw: email.raw)
    Delivery::ReturnPath.stubs(:find_delivery).with(@return_path).returns(delivery)

    email.correlate_bounce

    assert email.reload.delivered?
    assert email.forwarded_at.present?
  end

  test "an invalid or expired token does not crash and creates no suppression" do
    email = InboundEmail.create!(domain: @domain, mail_from: "", rcpt_to: @return_path, raw: dsn_raw)
    Delivery::ReturnPath.stubs(:find_delivery).with(@return_path).returns(nil)

    assert_no_difference -> { Suppression.count } do
      assert_nothing_raised { email.correlate_bounce }
    end

    assert email.reload.bounced?
  end

  private
    def deliver(from:, to:, raw:)
      mx_deliver(port: @port, from: from, to: to, raw: raw)
    end

    def dsn_raw
      "From: MAILER-DAEMON@mx.example.com\r\nSubject: Undelivered Mail Returned to Sender\r\n" \
        "Content-Type: multipart/report; report-type=delivery-status; boundary=\"BB\"\r\n\r\n" \
        "--BB\r\nContent-Type: text/plain\r\n\r\nDelivery to the following recipient failed permanently.\r\n\r\n" \
        "--BB\r\nContent-Type: message/delivery-status\r\n\r\nReporting-MTA: dns; mx.example.com\r\n\r\n" \
        "Final-Recipient: rfc822; recipient@example.com\r\nAction: failed\r\nStatus: 5.1.1\r\n\r\n--BB--\r\n"
    end
end
