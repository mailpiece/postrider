require "test_helper"
require "mailauth"
require "mailresolver/testing"

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

  test "records the connecting host's name once it resolved back" do
    stub_mailauth(iprev: "pass", remote_host: "mail.sender.example")

    verdicts = authenticate

    assert_equal "pass", verdicts[:iprev]
    assert_equal "mail.sender.example", verdicts[:remote_host]
  end

  test "records no host name when the reverse name did not resolve back" do
    stub_mailauth(iprev: "fail")

    verdicts = authenticate

    assert_equal "fail", verdicts[:iprev]
    assert_nil verdicts[:remote_host]
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

  test "records a temporary error when the gem raises, and reports why" do
    ::MailAuth.stubs(:authenticate).raises(::MailResolver::Timeout, "timed out resolving TXT sender.example")
    Rails.error.expects(:report).with(instance_of(::MailResolver::Timeout), severity: :warning)

    verdicts = authenticate

    assert_equal "temperror", verdicts[:spf]
    assert_equal "temperror", verdicts[:dkim]
    assert_equal "temperror", verdicts[:dmarc]
    assert_equal "temperror", verdicts[:iprev]
    assert_nil verdicts[:dmarc_policy]
    assert_nil verdicts[:arc]
    assert_nil verdicts[:arc_sealer]
    assert_nil verdicts[:remote_host]
    assert_not verdicts[:from_aligned]
    assert_equal "#{Relay.hostname}; iprev=temperror; spf=temperror; dkim=temperror; dmarc=temperror",
      verdicts[:authentication_results].gsub(/\r\n\s+/, " ")
  end

  test "settles on the verdicts when every check finished" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "pass")

    assert_equal "pass", settle[:dmarc]
  end

  test "leaves unsettled an SPF check or DKIM signature aligned with the From that failed for now" do
    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "temperror", dkim: "none", dmarc: "none"))
    assert_nil settle

    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "fail", dkim: "temperror", dmarc: "fail", aligned: true))
    assert_nil settle
  end

  test "settles when nothing that failed for now could vouch for the From on a retry" do
    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "pass", spf_domain: "bounces.unrelated.example", dkim: "none", dmarc: "temperror"))
    assert_equal "temperror", settle[:dmarc]
    assert_not settle[:from_aligned]

    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "fail", dkim: "temperror", dmarc: "fail"))
    assert_equal "temperror", settle[:dkim]

    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "temperror", spf_domain: "bounces.unrelated.example", dkim: "none", dmarc: "none"))
    assert_equal "temperror", settle[:spf]
  end

  test "settles once DMARC or an aligned pass vouches for the sender, whatever failed for now" do
    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "temperror", dkim: "pass", dmarc: "none", aligned: true))
    assert_equal "temperror", settle[:spf]

    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "none", dkim: "pass", dmarc: "temperror", aligned: true))
    assert_equal "temperror", settle[:dmarc]

    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "pass", dkim: "pass", dmarc: "pass").then do |result|
      result.with(dkim: ::MailAuth::DkimResult.new(signatures: [ ::MailAuth::Signature.new(status: "temperror"), *result.dkim.signatures ]))
    end)
    assert_equal "pass", settle[:dkim]
  end

  test "settles once a trusted sealer's passing ARC chain vouches for the sender, whatever failed for now" do
    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "temperror", dkim: "none", dmarc: "fail", arc: "pass", arc_sealer: "eur.microsoft.com"))
    assert_equal "temperror", settle[:spf]
  end

  test "leaves unsettled what failed for now when the ARC chain failed or its sealer is not trusted" do
    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "temperror", dkim: "none", dmarc: "fail", arc: "fail", arc_sealer: "microsoft.com"))
    assert_nil settle

    ::MailAuth.stubs(:authenticate).returns(result_of(spf: "temperror", dkim: "none", dmarc: "fail", arc: "pass", arc_sealer: "evilmicrosoft.com"))
    assert_nil settle
  end

  test "settles despite a reverse name that failed for now" do
    stub_mailauth(spf: "fail", dkim: "none", dmarc: "none", iprev: "temperror")
    assert_equal "temperror", settle[:iprev]
  end

  test "authenticates over the shared resolver, every lookup cut to end within its time" do
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1
    zone = MailResolver::Testing::FakeResolver.new
    InboundAuthentication::MailAuth.resolver.expects(:with_deadline).with { (it - deadline).between?(0, 0.5) }.returns(zone)
    ::MailAuth.expects(:authenticate).with(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example",
      mta: "relay.example", resolver: zone).returns(result_of(spf: "pass", dkim: "pass", dmarc: "pass"))

    assert_equal "pass", settle(within: 1)[:dmarc]
  end

  test "leaves unsettled, by its time, a sender whose DNS doesn't answer" do
    ::MailAuth.unstub(:authenticate)

    MailResolver::Testing::LocalNameserver.answering(nil, timeouts: MailResolver::Resolver::TIMEOUTS) do |resolver|
      InboundAuthentication::MailAuth.stubs(:resolver).returns(resolver)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_nil settle(within: 0.3)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 0.3 + MailResolver::Resolver::DEADLINE_MARGIN + 0.5
    end
  end

  test "leaves unsettled, without authenticating, when every slot is taken" do
    ::MailAuth.expects(:authenticate).never
    slots = MailGate::Slots.new(1)
    slots.claim

    assert_nil settle(slots:)
  end

  test "frees its slot once authenticated" do
    stub_mailauth(spf: "pass", dkim: "pass", dmarc: "pass")
    slots = MailGate::Slots.new(1)

    2.times { assert_equal "pass", settle(slots:)[:dmarc] }
  end

  test "settles on nothing, reporting why and freeing its slot, when authentication crashes" do
    ::MailAuth.stubs(:authenticate).raises(RuntimeError, "boom")
    Rails.error.expects(:report).with(instance_of(RuntimeError), severity: :warning).once
    slots = MailGate::Slots.new(1)

    assert_nil settle(slots:)
    assert slots.claim
  end

  private
    def settle(within: 1, slots: nil)
      InboundAuthentication.settled_verdicts(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example",
        within:, slots:)
    end

    def authenticate
      InboundAuthentication.verdicts(RAW, ip: "203.0.113.1", helo: "sender.example", mail_from: "person@sender.example")
    end

    def result_of(spf:, dkim:, dmarc:, aligned: false, spf_domain: "sender.example", arc: "none", arc_sealer: nil)
      ::MailAuth::Result.new(
        spf: ::MailAuth::SpfResult.new(status: spf, domain: spf_domain),
        dkim: ::MailAuth::DkimResult.new(signatures: [ ::MailAuth::Signature.new(status: dkim, domain: "sender.example", aligned:) ]),
        dmarc: ::MailAuth::DmarcResult.new(status: dmarc, policy: "reject"),
        arc: arc_result(arc, arc_sealer),
        authentication_results: "relay.example; spf=#{spf}; dkim=#{dkim}; dmarc=#{dmarc}"
      )
    end
end
