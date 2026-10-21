require "test_helper"
require "mailauth"

class InboundAuthentication::MailAuthTest < ActiveSupport::TestCase
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

  test "returns the gem's verdicts" do
    stub_mailauth(spf: "pass", dkim: "fail", dmarc: "softfail")

    verdicts = authenticate

    assert_equal "pass", verdicts[:spf]
    assert_equal "fail", verdicts[:dkim]
    assert_equal "softfail", verdicts[:dmarc]
  end

  test "records the policy the domain published alongside its verdict" do
    stub_mailauth(spf: "pass", dkim: "fail", dmarc: "fail", dmarc_policy: "reject")

    verdicts = authenticate

    assert_equal "fail", verdicts[:dmarc]
    assert_equal "reject", verdicts[:dmarc_policy]
  end

  test "records no policy when the domain publishes no DMARC record" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "none")

    verdicts = authenticate

    assert_equal "none", verdicts[:dmarc]
    assert_nil verdicts[:dmarc_policy]
  end

  test "records the chain status and the newest sealer when a chain exists" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "fail", arc: "pass", arc_sealer: "lists.example.org")

    verdicts = authenticate

    assert_equal "pass", verdicts[:arc]
    assert_equal "lists.example.org", verdicts[:arc_sealer]
  end

  test "records no sealer when the message carries no chain" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "pass")

    verdicts = authenticate

    assert_equal "none", verdicts[:arc]
    assert_nil verdicts[:arc_sealer]
  end

  # The authserv-id names this relay; without it every seal we write would read "unknown".
  test "hands the gem the message, the envelope it arrived with, and this relay's name" do
    ::MailAuth.expects(:authenticate)
      .with(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example",
        mta: "relay.example", resolver: InboundAuthentication::MailAuth.resolver)
      .returns(result_of(spf: "pass", dkim: "pass", dmarc: "pass"))

    assert_equal "pass", authenticate[:spf]
  end

  test "keeps the Authentication-Results the gem wrote, so a later seal states what this hop concluded" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "pass")

    assert_equal "test; spf=pass; dkim=pass; dmarc=pass; arc=none", authenticate[:authentication_results]
  end

  test "returns no verdict when the gem raises, and reports why" do
    ::MailAuth.stubs(:authenticate).raises(::MailResolver::Timeout, "timed out resolving TXT sender.example")
    Rails.error.expects(:report).with(instance_of(::MailResolver::Timeout), severity: :warning)

    verdicts = authenticate

    assert_nil verdicts[:spf]
    assert_nil verdicts[:dkim]
    assert_nil verdicts[:dmarc]
    assert_nil verdicts[:dmarc_policy]
    assert_nil verdicts[:arc]
    assert_nil verdicts[:arc_sealer]
    assert_nil verdicts[:authentication_results]
  end

  private
    def authenticate
      InboundAuthentication.verdicts(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example")
    end

    def result_of(spf:, dkim:, dmarc:)
      ::MailAuth::Result.new(
        spf: ::MailAuth::SpfResult.new(status: spf, domain: "sender.example"),
        dkim: ::MailAuth::DkimResult.new(signatures: [ ::MailAuth::Signature.new(status: dkim, domain: "sender.example") ]),
        dmarc: ::MailAuth::DmarcResult.new(status: dmarc, policy: "reject"),
        authentication_results: "relay.example; spf=#{spf}; dkim=#{dkim}; dmarc=#{dmarc}"
      )
    end
end
