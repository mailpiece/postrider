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

  test "strips a pre-existing header claiming our own authserv-id" do
    forged = "Authentication-Results: relay.example; spf=pass smtp.mailfrom=attacker@evil.example\r\n#{RAW}"

    stripped = InboundAuthentication.strip(forged)

    refute_includes stripped, "attacker@evil.example"
    assert_includes stripped, "Body."
  end

  test "strips every inbound Authentication-Results, whatever its authserv-id, comment, obs-WSP colon, or fold" do
    [
      "Authentication-Results: relay.example; dkim=pass header.d=trusted.example",
      "Authentication-Results: someone-elses-relay.example; dkim=pass header.d=trusted.example",
      "Authentication-Results: (legit) relay.example; dkim=pass header.d=trusted.example",
      "Authentication-Results : relay.example; dkim=pass header.d=trusted.example",
      "Authentication-Results:\r\n\trelay.example; dkim=pass header.d=trusted.example",
      "Authentication-Results: RELAY.EXAMPLE; dkim=pass header.d=trusted.example"
    ].each do |forged|
      stripped = InboundAuthentication.strip("#{forged}\r\n#{RAW}")

      refute_includes stripped, "trusted.example", "failed to strip: #{forged.inspect}"
    end
  end

  test "strips an Authentication-Results with deeply nested parens cheaply, never entering a quadratic parse" do
    nested = "#{"(" * 50_000}#{")" * 50_000}"
    pathological = "Authentication-Results: #{nested} relay.example; dkim=pass header.d=trusted.example"

    stripped = Timeout.timeout(5) do
      InboundAuthentication.strip("#{pathological}\r\n#{RAW}")
    end

    refute_includes stripped, "trusted.example"
  end

  private
    def authenticate
      InboundAuthentication.verdicts(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example")
    end
end
