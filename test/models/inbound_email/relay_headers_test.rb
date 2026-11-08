require "test_helper"

class InboundEmail::RelayHeadersTest < ActiveSupport::TestCase
  RAW = "From: a@test.com\r\nSubject: Hello\r\n\r\nA body.\r\n".freeze

  setup do
    stub_env RELAY_HOSTNAME: "mx.example"
  end

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

  test "states no results when we concluded none, so the first Authentication-Results is always ours" do
    email = create_email

    assert_includes header_section(email.relayable_raw), "Authentication-Results: mx.example;  none"
  end

  test "says what the spam check concluded, with no level below a point and no tests when none matched" do
    email = create_email
    email.track_event "scored", action: "no_action", score: -0.5, complete: true, symbols: []

    assert_includes header_section(email.relayable_raw), "X-Spam-Flag: NO\r\nX-Spam-Score: -0.5\r\n" \
      "X-Spam-Status: No, score=-0.5 tests=none\r\nX-Spam-Action: accept\r\n"
  end

  test "a reject is told as one, with its stars capped at fifty" do
    email = create_email
    email.track_event "scored", action: "reject", score: 72.04, complete: true, symbols: [ [ "BAYES_SPAM", 5.0, nil ] ]

    headers = header_section(email.relayable_raw)

    assert_includes headers, "X-Spam-Score: 72.0\r\nX-Spam-Level: #{"*" * 50}\r\n"
    assert_includes headers, "X-Spam-Status: Yes, score=72.0 tests=BAYES_SPAM\r\nX-Spam-Action: reject\r\n"
  end

  test "every X-Spam- field the sender wrote is taken out, folded lines and all, leaving its body alone" do
    email = create_inbound_email(raw: "x-spam-status: No,\r\n\tscore=-5.0\r\nFrom: a@test.com\r\nX-SPAM-Flag: NO\r\n" \
      "Subject: Hello\r\n\r\nX-Spam-Flag: quoted\r\n")
    email.track_event "scored", action: "reject", score: 16.0, complete: true, symbols: []

    assert email.relayable_raw.end_with?("X-Spam-Action: reject\r\nFrom: a@test.com\r\nSubject: Hello\r\n\r\nX-Spam-Flag: quoted\r\n")
    assert_equal 1, email.relayable_raw.scan(/^X-Spam-Status:/i).count
  end

  test "leaves the original message untouched below its own headers" do
    email = create_email

    assert_equal RAW, email.relayable_raw.delete_prefix(header_section(email.relayable_raw))
  end

  test "a recipient carrying a line break cannot open a header of its own" do
    email = create_email(rcpt_to: "support@example.com\r\nBcc: elsewhere@example.com")

    headers = header_section(email.relayable_raw)

    assert_includes headers, "Delivered-To: support@example.com Bcc: elsewhere@example.com"
    assert_no_match(/^Bcc:/, headers)
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
