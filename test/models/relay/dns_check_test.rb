require "test_helper"

class Relay::DnsCheckTest < ActiveSupport::TestCase
  setup do
    stub_env RELAY_HOSTNAME: "mx.example"
  end

  test "dns_records lists A/AAAA, MX, PTR, SPF, the sealing key and the challenge delegation, all on the relay hostname while no mail domain is set" do
    check = Relay::DnsCheck.instance
    types = check.dns_records.map(&:type)

    assert_equal %w[ A/AAAA MX PTR TXT TXT NS ], types
    assert_equal "mx.example", check.dns_records.first.hostname
    assert_equal "10 mx.example.", check.dns_records.find { |record| record.type == "MX" }.value
    assert_equal "v=spf1 a:mx.example -all", check.dns_records[3].value
    assert_equal "arc._domainkey.mx.example", check.dns_records[4].hostname
    assert_equal "_acme-challenge.mx.example", check.dns_records.last.hostname
    assert_equal "mx.example.", check.dns_records.last.value
  end

  test "dns_records delegates one challenge name per hostname the certificate covers" do
    delegations = with_env(SUBMISSION_HOSTNAME: "smtp.example") do
      Relay::DnsCheck.instance.dns_records.select { |record| record.type == "NS" }
    end

    assert_equal %w[ _acme-challenge.mx.example _acme-challenge.smtp.example ], delegations.map(&:hostname)
    assert_equal [ "mx.example.", "mx.example." ], delegations.map(&:value)
    assert_equal [ :acme_delegation, :acme_delegation ], delegations.map(&:check)
  end

  test "dns_records adds an A/AAAA for the submission hostname when it differs" do
    addresses = with_env(SUBMISSION_HOSTNAME: "smtp.example") do
      Relay::DnsCheck.instance.dns_records.select { |record| record.type == "A/AAAA" }
    end

    assert_equal %w[ mx.example smtp.example ], addresses.map(&:hostname)
  end

  test "dns_records moves the MX and SPF onto the mail domain, and gives it an A/AAAA, when it differs" do
    records = with_env(RELAY_MAIL_DOMAIN: "mailer.example") { Relay::DnsCheck.instance.dns_records }
    mx = records.find { |record| record.type == "MX" }
    spf = records.find { |record| record.type == "TXT" }

    assert_equal %w[ mx.example mailer.example ], records.select { |record| record.type == "A/AAAA" }.map(&:hostname)
    assert_equal "mailer.example", mx.hostname
    assert_equal "10 mx.example.", mx.value
    assert_equal "mailer.example", spf.hostname
    assert_equal "v=spf1 a:mailer.example -all", spf.value
  end

  test "dns_records name the check behind each record, and none for an MX nothing looks at" do
    records = Relay::DnsCheck.instance.dns_records

    assert_equal [ :address, nil, :ptr, :spf, :sealing_key, :acme_delegation ], records.map(&:check)
    assert_equal [ "Relay hostname", "Bounces", "Reverse DNS", "SPF", "ARC sealing key", "Certificate challenge" ], records.map(&:purpose)
  end

  test "dns_records put a distinct mail domain's A/AAAA and MX under its one check, even when submission shares the name" do
    records = with_env(RELAY_MAIL_DOMAIN: "mailer.example", SUBMISSION_HOSTNAME: "mailer.example") do
      Relay::DnsCheck.instance.dns_records.select { |record| record.hostname == "mailer.example" }
    end

    assert_equal [ [ "A/AAAA", :mail_domain ], [ "MX", :mail_domain ], [ "TXT", :spf ], [ "A/AAAA", :submission_address ] ],
      records.map { |record| [ record.type, record.check ] }
  end

  test "dns_records shows the real address once resolved, instead of asking the operator for it" do
    stub_dns addresses: %w[ 203.0.113.10 2001:db8::10 ],
      names: { "203.0.113.10" => "mx.example", "2001:db8::10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    check.check_dns

    records = check.dns_records
    assert_equal "203.0.113.10 and 2001:db8::10", records.find { |record| record.type == "A/AAAA" }.value

    ptr_records = records.select { |record| record.type == "PTR" }
    assert_equal %w[ 203.0.113.10 2001:db8::10 ], ptr_records.map(&:hostname)
    assert_equal [ "mx.example.", "mx.example." ], ptr_records.map(&:value)
  end

  test "check_dns records every address, its PTR, and SPF when DNS is healthy" do
    stub_dns addresses: %w[ 203.0.113.10 2001:db8::10 ],
      names: { "203.0.113.10" => "mx.example", "2001:db8::10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    assert check.check_dns

    check.reload
    assert_equal %w[ 203.0.113.10 2001:db8::10 ], check.addresses.map(&:address)
    assert check.address_ok?
    assert_equal %w[ mx.example mx.example ], check.addresses.map(&:ptr_hostname)
    assert check.ptr_ok?
    assert check.spf_ok?
    assert check.dns_ok?
    assert check.dns_checked?
  end

  test "check_dns compares the PTR to the hostname case-insensitively" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    with_env(RELAY_HOSTNAME: "MX.Example") do
      assert Relay::DnsCheck.instance.check_dns
    end
  end

  test "check_dns is invalid when one address's PTR points somewhere else, and names it" do
    stub_dns addresses: %w[ 203.0.113.10 203.0.113.11 ],
      names: { "203.0.113.10" => "mx.example", "203.0.113.11" => "other.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.ptr_invalid?
    assert_match "203.0.113.11 → other.example (expected mx.example)", check.ptr_error
    assert_no_match "203.0.113.10", check.ptr_error
  end

  test "check_dns is missing when no address has a PTR at all" do
    stub_dns addresses: %w[ 203.0.113.10 ], txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.ptr_missing?
    assert check.addresses.all? { |address| address.ptr_hostname.nil? }
  end

  test "check_dns names the specific address missing its PTR when others are fine" do
    stub_dns addresses: %w[ 203.0.113.10 203.0.113.11 ],
      names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.ptr_invalid?
    assert_match "203.0.113.11 → no PTR (expected mx.example)", check.ptr_error
  end

  test "check_dns is missing when no SPF record exists at all" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" }

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.spf_missing?
    assert_equal "Publish v=spf1 a:mx.example -all at mx.example", check.spf_error
  end

  test "check_dns is missing when TXT records exist but none of them are SPF" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "some-other-verification=abc123" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.spf_missing?
  end

  test "check_dns accepts a published SPF record with an extra include: and a softfail qualifier" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example include:_spf.google.com ~all" ]

    check = Relay::DnsCheck.instance
    check.check_dns

    assert check.spf_ok?
  end

  test "check_dns is invalid, and names what's missing, when SPF exists without our mechanism" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a -all" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.spf_invalid?
    assert_equal "SPF at mx.example doesn't include a:mx.example", check.spf_error
  end

  test "check_dns compares SPF mechanisms as whole tokens, not substrings" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.exampleton -all" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.spf_invalid?
  end

  # A record good enough for the relay hostname must not stand in for the mail domain's.
  test "check_dns evaluates SPF at the mail domain, not the relay hostname, when they differ" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" }
    DnsResolver.stubs(:txt).with("mx.example").returns([ "v=spf1 a:mx.example -all" ])
    DnsResolver.stubs(:txt).with("mailer.example").returns([ "v=spf1 a -all" ])

    with_env(RELAY_MAIL_DOMAIN: "mailer.example") do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.spf_invalid?
      assert_equal "SPF at mailer.example doesn't include a:mailer.example", check.spf_error
    end
  end

  test "check_dns is OK for the mail domain when it resolves here and its MX points at the relay" do
    stub_mail_domain_dns "mailer.example", resolving_to: %w[ 203.0.113.10 ], exchangers: %w[ mx.example ] do
      check = Relay::DnsCheck.instance
      check.check_dns

      assert check.mail_domain_ok?
      assert_nil check.mail_domain_error
    end
  end

  test "check_dns is missing when the mail domain has no A/AAAA record" do
    stub_mail_domain_dns "mailer.example", resolving_to: [], exchangers: %w[ mx.example ] do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.mail_domain_missing?
      assert_equal "No A/AAAA record yet for mailer.example", check.mail_domain_error
    end
  end

  # An SPF a: mechanism resolving to someone else's address is worse than none at all.
  test "check_dns is invalid when the mail domain resolves somewhere other than this server" do
    stub_mail_domain_dns "mailer.example", resolving_to: %w[ 198.51.100.7 ], exchangers: %w[ mx.example ] do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.mail_domain_invalid?
      assert_equal "mailer.example resolves to 198.51.100.7, not this server", check.mail_domain_error
    end
  end

  test "check_dns is missing when the mail domain resolves but publishes no MX" do
    stub_mail_domain_dns "mailer.example", resolving_to: %w[ 203.0.113.10 ], exchangers: [] do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.mail_domain_missing?
      assert_match "bounces have nowhere to land", check.mail_domain_error
    end
  end

  test "check_dns leaves the mail domain unchecked when it matches the relay hostname" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    check.check_dns

    assert_nil check.mail_domain_status
    assert check.dns_ok?
  end

  test "check_dns checks SPF independently of address status" do
    stub_dns txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    assert check.address_missing?
    assert check.ptr_invalid?
    assert check.spf_ok?
  end

  test "check_dns explains itself when the hostname isn't configured" do
    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil) do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.address_invalid?
      assert check.spf_invalid?
      assert_match "RELAY_HOSTNAME", check.address_error
    end
  end

  test "a transient DNS failure leaves a healthy check's statuses untouched" do
    check = Relay::DnsCheck.instance
    check.update!(address_status: :ok, ptr_status: :ok, spf_status: :ok)
    check.addresses.create!(address: "203.0.113.10", ptr_hostname: "mx.example", expected_ptr_hostname: "mx.example")

    DnsResolver.stubs(:addresses).raises(DnsResolver::TransientError, "DNS resolv timeout: mx.example")
    DnsResolver.stubs(:name).raises(DnsResolver::TransientError, "DNS resolv timeout: 10.113.0.203.in-addr.arpa")
    DnsResolver.stubs(:txt).raises(DnsResolver::TransientError, "DNS resolv timeout: mx.example")

    assert check.check_dns

    check.reload
    assert check.address_ok?
    assert check.ptr_ok?
    assert check.spf_ok?
    assert_match "DNS resolv timeout", check.spf_error
  end

  test "a never-checked relay stays unchecked when its first check times out" do
    DnsResolver.stubs(:addresses).raises(DnsResolver::TransientError, "DNS resolv timeout: mx.example")
    DnsResolver.stubs(:name).raises(DnsResolver::TransientError, "DNS resolv timeout")
    DnsResolver.stubs(:txt).raises(DnsResolver::TransientError, "DNS resolv timeout: mx.example")

    check = Relay::DnsCheck.instance
    assert_not check.check_dns

    check.reload
    assert_nil check.address_status
    assert_nil check.ptr_status
    assert_nil check.spf_status
  end

  test "a genuine negative answer still marks the relay's address record missing" do
    check = Relay::DnsCheck.instance
    check.update!(address_status: :ok, ptr_status: :ok, spf_status: :ok)
    check.addresses.create!(address: "203.0.113.10", ptr_hostname: "mx.example", expected_ptr_hostname: "mx.example")

    stub_dns

    assert_not check.check_dns

    check.reload
    assert check.address_missing?
    assert check.ptr_invalid?
    assert check.spf_missing?
    assert_empty check.addresses
  end

  test "check_dns passes the delegation when every challenge name's NS names this relay, whatever the hostname's case" do
    stub_acme_delegation_dns "_acme-challenge.mx.example" => [ "mx.example" ], "_acme-challenge.smtp.example" => [ "other.example", "mx.example" ]

    with_env(RELAY_HOSTNAME: "MX.Example", SUBMISSION_HOSTNAME: "smtp.example") do
      check = Relay::DnsCheck.instance
      check.check_dns

      assert check.acme_delegation_ok?
      assert_nil check.acme_delegation_error
    end
  end

  test "check_dns is missing when a challenge name has no NS record, and names it" do
    stub_acme_delegation_dns "_acme-challenge.mx.example" => [ "mx.example" ], "_acme-challenge.smtp.example" => []

    with_env(SUBMISSION_HOSTNAME: "smtp.example") do
      check = Relay::DnsCheck.instance
      check.check_dns

      assert check.acme_delegation_missing?
      assert_equal "No NS record yet for _acme-challenge.smtp.example", check.acme_delegation_error
    end
  end

  test "check_dns is invalid when a challenge name is delegated elsewhere" do
    stub_acme_delegation_dns "_acme-challenge.mx.example" => [ "ns1.provider.example", "ns2.provider.example" ]

    check = Relay::DnsCheck.instance
    check.check_dns

    assert check.acme_delegation_invalid?
    assert_equal "_acme-challenge.mx.example is delegated to ns1.provider.example and ns2.provider.example, not mx.example", check.acme_delegation_error
  end

  test "the delegation is reported, not gated on" do
    stub_acme_delegation_dns "_acme-challenge.mx.example" => []

    assert Relay::DnsCheck.instance.check_dns
  end

  test "the delegation isn't checked where no certificate is ordered" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" }, txt: [ "v=spf1 a:mx.example -all" ]
    DnsResolver.expects(:ns).never

    check = Relay::DnsCheck.instance
    check.check_dns

    assert_nil check.acme_delegation_status
  end

  test "check_dns_later enqueues the check" do
    assert_enqueued_with job: DnsCheckJob, args: [ Relay::DnsCheck.instance ] do
      Relay::DnsCheck.instance.check_dns_later
    end
  end

  test "check_dns replaces the previous round's addresses instead of accumulating them" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]
    check = Relay::DnsCheck.instance
    check.check_dns

    stub_dns addresses: %w[ 203.0.113.11 ], names: { "203.0.113.11" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]
    check.check_dns

    check.reload
    assert_equal %w[ 203.0.113.11 ], check.addresses.map(&:address)
  end

  test "check_dns is OK when the submission hostname resolves to this server too" do
    stub_submission_dns "smtp.example", resolving_to: %w[ 203.0.113.10 ] do
      check = Relay::DnsCheck.instance
      assert check.check_dns

      assert check.submission_address_ok?
      assert check.dns_ok?
    end
  end

  test "check_dns is missing when the submission hostname doesn't resolve, and isn't OK overall" do
    stub_submission_dns "smtp.example", resolving_to: [] do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.submission_address_missing?
      assert_equal "No A/AAAA record yet for smtp.example", check.submission_address_error
      assert_not check.dns_ok?
    end
  end

  test "check_dns is invalid when the submission hostname resolves somewhere else" do
    stub_submission_dns "smtp.example", resolving_to: %w[ 198.51.100.7 ] do
      check = Relay::DnsCheck.instance
      assert_not check.check_dns

      assert check.submission_address_invalid?
      assert_equal "smtp.example resolves to 198.51.100.7, not this server", check.submission_address_error
    end
  end

  test "check_dns leaves the submission address unchecked when it's the relay hostname" do
    stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
      txt: [ "v=spf1 a:mx.example -all" ]

    check = Relay::DnsCheck.instance
    assert check.check_dns

    assert_nil check.submission_address_status
    assert check.dns_ok?
  end

  test "there is only ever one relay DNS check" do
    check = Relay::DnsCheck.instance

    assert_equal check, Relay::DnsCheck.instance
    assert_raises ActiveRecord::RecordNotUnique do
      Relay::DnsCheck.create!
    end
  end

  test "check_dns is OK when the published ARC key is the one we seal forwards with" do
    stub_sealing_key_dns [ Relay::SealingKey.instance.txt_value ]

    check = Relay::DnsCheck.instance
    assert check.check_dns

    assert check.sealing_key_ok?
    assert_nil check.sealing_key_error
  end

  # Forwarding degrades without it, so it's reported rather than gating the relay.
  test "check_dns reports a missing sealing key while still calling the relay ready" do
    stub_sealing_key_dns []

    check = Relay::DnsCheck.instance
    assert check.check_dns

    assert check.sealing_key_missing?
    assert_equal "No ARC sealing key published at arc._domainkey.mx.example", check.sealing_key_error
    assert check.dns_ok?
  end

  test "check_dns is invalid when the record at the sealing selector is somebody else's key" do
    stub_sealing_key_dns [ DkimKey.txt_value(DkimKey.load(DkimKey.generate)) ]

    check = Relay::DnsCheck.instance
    check.check_dns

    assert check.sealing_key_invalid?
    assert_match "doesn't match the key we seal forwards with", check.sealing_key_error
  end

  test "dns_records includes the sealing key TXT under the mail domain" do
    record = with_env(RELAY_MAIL_DOMAIN: "mailer.example") do
      Relay::DnsCheck.instance.dns_records.find { |candidate| candidate.hostname.start_with?("arc._domainkey") }
    end

    assert_equal "arc._domainkey.mailer.example", record.hostname
    assert_equal Relay::SealingKey.instance.txt_value, record.value
  end

  private
    def stub_dns(...)
      stub_dns_resolver(...)
    end

    def stub_mail_domain_dns(mail_domain, resolving_to:, exchangers:, &)
      stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" }
      DnsResolver.stubs(:txt).with(mail_domain).returns([ "v=spf1 a:#{mail_domain} -all" ])
      DnsResolver.stubs(:addresses).with(mail_domain).returns(resolving_to)
      DnsResolver.stubs(:mx).with(mail_domain).returns(exchangers)
      with_env(RELAY_MAIL_DOMAIN: mail_domain, &)
    end

    def stub_sealing_key_dns(records)
      stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" }
      DnsResolver.stubs(:txt).with("mx.example").returns([ "v=spf1 a:mx.example -all" ])
      DnsResolver.stubs(:txt).with(Relay::SealingKey.instance.host).returns(records)
    end

    def stub_acme_delegation_dns(nameservers)
      Relay.stubs(:acme?).returns(true)
      stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" }, txt: [ "v=spf1 a:mx.example -all" ]
      nameservers.each { |name, servers| DnsResolver.stubs(:ns).with(name).returns(servers) }
    end

    def stub_submission_dns(submission_hostname, resolving_to:, &)
      stub_dns addresses: %w[ 203.0.113.10 ], names: { "203.0.113.10" => "mx.example" },
        txt: [ "v=spf1 a:mx.example -all" ]
      DnsResolver.stubs(:addresses).with(submission_hostname).returns(resolving_to)
      with_env(SUBMISSION_HOSTNAME: submission_hostname, &)
    end
end
