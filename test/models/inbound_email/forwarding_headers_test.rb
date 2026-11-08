require "test_helper"

class InboundEmail::ForwardingHeadersTest < ActiveSupport::TestCase
  DESTINATION = "dest@elsewhere.example"
  RAW = "From: a@test.com\r\nSubject: Hello\r\n\r\nA body.\r\n".freeze

  test "names the domain that forwarded, where it went, and the mailbox it came from" do
    headers = header_section create_email(rcpt_to: "list@example.com")

    assert_includes headers, "#{InboundEmail::Forwarding::TRACE_HEADER}: example.com"
    assert_includes headers, "#{InboundEmail::Forwarding::TRACE_HEADER}-To: #{DESTINATION}"
    assert_includes headers, "#{InboundEmail::Forwarding::TRACE_HEADER}-For: list@example.com #{DESTINATION}"
  end

  test "carries the headers the scorer asked for, in its order, below our own" do
    email = create_email
    email.track_event "scored", action: "add_header", score: 6.5, complete: true, symbols: [],
      headers: [ [ "X-Spam-Flag", "YES" ], [ "X-Spam-Score", "6.5" ], [ "X-Spam-Action", "tag" ] ]

    assert header_section(email).end_with?("-For: list@example.com #{DESTINATION}\r\n" \
      "X-Spam-Flag: YES\r\nX-Spam-Score: 6.5\r\nX-Spam-Action: tag\r\n")
  end

  test "mail never scored carries no spam headers, not even the sender's own" do
    email = create_inbound_email(raw: "X-Spam-Flag: NO\r\n#{RAW}")

    assert_no_match(/^X-Spam-/, forwardable(email))
  end

  test "leaves the original message untouched below its own headers" do
    email = create_email

    assert_equal RAW, forwardable(email).delete_prefix(header_section(email))
  end

  test "a recipient carrying a line break cannot open a header of its own" do
    headers = header_section create_email(rcpt_to: "list@example.com\r\nBcc: elsewhere@example.com")

    assert_includes headers, "#{InboundEmail::Forwarding::TRACE_HEADER}-For: list@example.com Bcc: elsewhere@example.com #{DESTINATION}"
    assert_equal 3, headers.lines.count
  end

  private
    def create_email(rcpt_to: "list@example.com")
      create_inbound_email(rcpt_to: rcpt_to, raw: RAW)
    end

    def forwardable(email)
      InboundEmail::ForwardingHeaders.new(email, DESTINATION).prepended_to(email.raw)
    end

    def header_section(email)
      forwardable(email).then { |raw| raw[0...raw.index(RAW)] }
    end
end
