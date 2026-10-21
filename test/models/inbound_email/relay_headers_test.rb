require "test_helper"

class InboundEmail::RelayHeadersTest < ActiveSupport::TestCase
  RAW = "From: a@test.com\r\nSubject: Hello\r\n\r\nA body.\r\n".freeze

  test "names the mailbox the message arrived at, and the mailpiece" do
    email = create_email(rcpt_to: "support@example.com")

    headers = header_section(email.relayable_raw)

    assert_includes headers, "Delivered-To: support@example.com"
    assert_includes headers, "X-PostRider-Mailpiece-Id: #{email.mailpiece.id}"
  end

  test "stamps the authentication results we concluded, since the consumer never saw the session" do
    email = create_email(authentication_results: "mx.test; spf=pass smtp.mailfrom=a@test.com; dkim=pass header.d=test.com")

    assert_includes header_section(email.relayable_raw),
      "Authentication-Results: mx.test; spf=pass smtp.mailfrom=a@test.com; dkim=pass header.d=test.com"
  end

  test "omits the authentication results when we concluded none, so an absent header never reads as a pass" do
    email = create_email

    assert_no_match(/Authentication-Results/i, header_section(email.relayable_raw))
  end

  test "leaves the original message untouched below its own headers" do
    email = create_email

    assert_equal RAW, email.relayable_raw.delete_prefix(header_section(email.relayable_raw))
  end

  test "a recipient carrying a line break cannot open a header of its own" do
    email = create_email(rcpt_to: "support@example.com\r\nBcc: elsewhere@example.com")

    headers = header_section(email.relayable_raw)

    assert_includes headers, "Delivered-To: support@example.com Bcc: elsewhere@example.com"
    assert_equal 2, headers.lines.count
  end

  test "an incinerated message has nothing to relay" do
    email = create_email
    email.incinerate

    assert_nil email.reload.relayable_raw
  end

  private
    def create_email(rcpt_to: "support@example.com", **attributes)
      create_inbound_email(rcpt_to: rcpt_to, raw: RAW, **attributes)
    end

    def header_section(raw)
      raw[0...raw.index(RAW)]
    end
end
