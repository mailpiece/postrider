require "test_helper"

class Domain::DnsChecksTest < ActiveSupport::TestCase
  test "check_mx_record is OK when an MX record points at this relay" do
    domain = domains(:unverified)
    DnsResolver.stubs(:mx).with("unverified.example").returns([ "relay.example.com" ])
    DnsResolver.stubs(:cname).with("unverified.example").returns([])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_mx_record)
    end

    assert domain.mx_ok?
    assert_nil domain.mx_error
  end

  test "check_mx_record is OK when a CNAME points at this relay" do
    domain = domains(:unverified)
    DnsResolver.stubs(:mx).with("unverified.example").returns([])
    DnsResolver.stubs(:cname).with("unverified.example").returns([ "relay.example.com" ])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_mx_record)
    end

    assert domain.mx_ok?
    assert_nil domain.mx_error
  end

  test "check_mx_record is Missing when neither MX nor CNAME points at the relay" do
    domain = domains(:unverified)
    DnsResolver.stubs(:mx).returns([])
    DnsResolver.stubs(:cname).returns([])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_mx_record)
    end

    assert domain.mx_missing?
    assert_match "No MX or CNAME", domain.mx_error
  end

  test "check_mx_record is Invalid when a CNAME points elsewhere" do
    domain = domains(:unverified)
    DnsResolver.stubs(:mx).returns([])
    DnsResolver.stubs(:cname).returns([ "mail.other.example" ])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_mx_record)
    end

    assert domain.mx_invalid?
    assert_match "doesn't point to relay.example.com", domain.mx_error
  end

  test "check_mx_record reports a clear error instead of crashing when the relay hostname isn't configured" do
    domain = domains(:unverified)

    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil) do
      domain.send(:check_mx_record)
    end

    assert domain.mx_invalid?
    assert_match "hostname isn't configured", domain.mx_error
  end

  test "check_dns_all_later enqueues a check for every domain" do
    assert_enqueued_jobs Domain.count, only: DnsCheckJob do
      Domain.check_dns_all_later
    end
  end

  test "check_dns records the statuses and when it ran" do
    domain = domains(:unverified)
    DnsResolver.stubs(:mx).returns([])
    DnsResolver.stubs(:txt).returns([])
    DnsResolver.stubs(:cname).returns([])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      assert_not domain.check_dns
    end

    assert domain.reload.mx_missing?
    assert domain.dkim_missing?
    assert domain.dns_checked?
  end

  test "check_dkim_record is OK when the published key matches the one we generated" do
    domain = domains(:unverified)
    DnsResolver.stubs(:txt).with("#{domain.dkim_selector}._domainkey.unverified.example").returns([ domain.dkim_record.value ])

    domain.send(:check_dkim_record)

    assert domain.dkim_ok?
    assert domain.verified?
  end

  test "check_dkim_record is Invalid when the published key is someone else's" do
    domain = domains(:unverified)
    DnsResolver.stubs(:txt).returns([ "v=DKIM1; k=rsa; p=SGVsbG8gdGhlcmU=" ])

    domain.send(:check_dkim_record)

    assert domain.dkim_invalid?
    assert_match "doesn't match", domain.dkim_error
  end

  test "check_dmarc_record is OK when a DMARC record with a policy is published" do
    domain = domains(:unverified)
    DnsResolver.stubs(:txt).with("_dmarc.unverified.example").returns([ "v=DMARC1; p=none; rua=mailto:dmarc-reports@unverified.example;" ])

    domain.send(:check_dmarc_record)

    assert domain.dmarc_ok?
    assert_nil domain.dmarc_error
  end

  test "check_dmarc_record is Missing when no DMARC record is published" do
    domain = domains(:unverified)
    DnsResolver.stubs(:txt).returns([])

    domain.send(:check_dmarc_record)

    assert domain.dmarc_missing?
    assert_match "No DMARC record", domain.dmarc_error
  end

  test "check_dmarc_record is Invalid when a DMARC record has no policy tag" do
    domain = domains(:unverified)
    DnsResolver.stubs(:txt).returns([ "v=DMARC1; rua=mailto:dmarc-reports@unverified.example;" ])

    domain.send(:check_dmarc_record)

    assert domain.dmarc_invalid?
    assert_match "no policy", domain.dmarc_error
  end

  test "check_return_path_record is OK when the CNAME points to this relay" do
    domain = domains(:unverified)
    DnsResolver.stubs(:cname).with("mailer.unverified.example").returns([ "relay.example.com" ])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_return_path_record)
    end

    assert domain.return_path_ok?
    assert_nil domain.return_path_error
  end

  test "check_return_path_record is Missing when no CNAME exists" do
    domain = domains(:unverified)
    DnsResolver.stubs(:cname).returns([])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_return_path_record)
    end

    assert domain.return_path_missing?
    assert_match "No CNAME record", domain.return_path_error
  end

  test "check_return_path_record is Invalid when the CNAME points elsewhere" do
    domain = domains(:unverified)
    DnsResolver.stubs(:cname).returns([ "mail.other.example" ])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      domain.send(:check_return_path_record)
    end

    assert domain.return_path_invalid?
    assert_match "doesn't point to relay.example.com", domain.return_path_error
  end

  test "check_return_path_record is OK when the CNAME points at a mail domain distinct from the MX hostname" do
    domain = domains(:unverified)
    DnsResolver.stubs(:cname).with("mailer.unverified.example").returns([ "mailer.relay.example" ])

    with_env(RELAY_HOSTNAME: "mx.relay.example", RELAY_MAIL_DOMAIN: "mailer.relay.example") do
      domain.send(:check_return_path_record)
    end

    assert domain.return_path_ok?
    assert_nil domain.return_path_error
  end

  test "check_return_path_record is Invalid when the CNAME still points at the MX hostname" do
    domain = domains(:unverified)
    DnsResolver.stubs(:cname).with("mailer.unverified.example").returns([ "mx.relay.example" ])

    with_env(RELAY_HOSTNAME: "mx.relay.example", RELAY_MAIL_DOMAIN: "mailer.relay.example") do
      domain.send(:check_return_path_record)
    end

    assert domain.return_path_invalid?
    assert_match "doesn't point to mailer.relay.example", domain.return_path_error
  end

  test "check_return_path_record reports a clear error when the relay hostname isn't configured" do
    domain = domains(:unverified)

    with_env(RELAY_HOSTNAME: nil, BASE_URL: nil, RELAY_MAIL_DOMAIN: nil) do
      domain.send(:check_return_path_record)
    end

    assert domain.return_path_invalid?
    assert_match "hostname isn't configured", domain.return_path_error
  end

  test "dns_ok? is true once MX and DKIM are OK" do
    domain = domains(:unverified)
    assert_not domain.dns_ok?

    domain.update!(mx_status: :ok, dkim_status: :ok)

    assert domain.dns_ok?
  end

  test "advanced_verified? and return_path_enabled? flip once DMARC and Return-Path check out" do
    domain = domains(:unverified)
    assert_not domain.advanced_verified?
    assert_not domain.return_path_enabled?

    domain.update!(dkim_status: :ok, dmarc_status: :ok, return_path_status: :ok)

    assert domain.advanced_verified?
    assert domain.return_path_enabled?
  end

  test "a domain that passes DKIM tracks a verification" do
    domain = domains(:unverified)

    assert_difference -> { Event.count }, 1 do
      domain.update!(dkim_status: :ok)
    end

    assert_equal "domain_verified", domain.events.last.action
  end

  test "a domain that loses DKIM tracks the loss and why" do
    domain = domains(:example)

    assert_difference -> { Event.count }, 1 do
      domain.update!(dkim_status: :missing, dkim_error: "No DKIM record exists at postrider._domainkey.example.com")
    end

    event = domain.events.last
    assert_equal "domain_verification_lost", event.action
    assert_equal "missing", event.particulars["status"]
    assert_match "No DKIM record exists", event.particulars["error"]
  end

  test "a domain that has never verified tracks nothing when its first check fails" do
    domain = domains(:unverified)

    assert_no_difference -> { Event.count } do
      domain.update!(dkim_status: :missing, dkim_error: "No DKIM record exists")
      domain.update!(dkim_status: :invalid, dkim_error: "The DKIM record doesn't match")
    end
  end

  test "a transient DNS failure leaves a verified domain verified and tracks no loss" do
    domain = domains(:example)
    domain.update!(mx_status: :ok, dmarc_status: :ok, return_path_status: :ok)

    DnsResolver.stubs(:mx).raises(DnsResolver::TransientError, "DNS resolv timeout: example.com")
    DnsResolver.stubs(:txt).raises(DnsResolver::TransientError, "DNS resolv timeout: example.com")
    DnsResolver.stubs(:cname).raises(DnsResolver::TransientError, "DNS resolv timeout: mailer.example.com")

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      assert_no_difference -> { Event.count } do
        assert domain.check_dns
      end
    end

    domain.reload
    assert domain.dkim_ok?
    assert domain.mx_ok?
    assert_match "DNS resolv timeout", domain.dkim_error
    assert domain.dns_checked?
  end

  test "a never-checked domain stays unchecked when its first check times out" do
    domain = domains(:unverified)

    DnsResolver.stubs(:mx).raises(DnsResolver::TransientError, "DNS resolv timeout: unverified.example")
    DnsResolver.stubs(:txt).raises(DnsResolver::TransientError, "DNS resolv timeout: unverified.example")
    DnsResolver.stubs(:cname).raises(DnsResolver::TransientError, "DNS resolv timeout: mailer.unverified.example")

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      assert_no_difference -> { Event.count } do
        assert_not domain.check_dns
      end
    end

    domain.reload
    assert_nil domain.dkim_status
    assert_nil domain.mx_status
  end

  test "a genuine negative answer still loses verification and tracks the loss" do
    domain = domains(:example)
    domain.update!(mx_status: :ok)

    DnsResolver.stubs(:mx).returns([])
    DnsResolver.stubs(:txt).returns([])
    DnsResolver.stubs(:cname).returns([])

    with_env(RELAY_HOSTNAME: "relay.example.com") do
      assert_difference -> { Event.count }, 1 do
        assert_not domain.check_dns
      end
    end

    assert domain.reload.dkim_missing?
    assert_equal "domain_verification_lost", domain.events.last.action
  end

  test "rechecking a domain whose DKIM status is unchanged tracks nothing" do
    domain = domains(:example)

    assert_no_difference -> { Event.count } do
      domain.update!(dns_checked_at: Time.current)
    end
  end
end
