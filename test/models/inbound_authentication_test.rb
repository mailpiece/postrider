require "test_helper"

class InboundAuthenticationTest < ActiveSupport::TestCase
  RAW = <<~RAW.gsub("\n", "\r\n")
    DKIM-Signature: v=1; a=rsa-sha256; c=relaxed/relaxed; d=sender.example;
      s=default; h=from:to:subject; bh=abc123; b=def456
    From: Sender <person@sender.example>
    To: list@postrider.example
    Subject: Hello

    Body.
  RAW

  setup do
    stub_env RELAY_HOSTNAME: "relay.example"
  end

  test "delegates to mailauth for SPF, DKIM, and DMARC" do
    stub_mailauth(spf: "pass", dkim: "fail", dmarc: "softfail")

    verdicts = authenticate

    assert_equal "pass", verdicts[:spf]
    assert_equal "fail", verdicts[:dkim]
    assert_equal "softfail", verdicts[:dmarc]
  end

  private
    def authenticate
      InboundAuthentication.verdicts(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example")
    end
end
