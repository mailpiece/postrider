require "test_helper"

class Relay::Certificate::RenewableTest < ActiveSupport::TestCase
  include CertificateTestHelper

  test "due_for_renewal? when no certificate exists yet" do
    assert Relay::Certificate.instance.due_for_renewal?
  end

  test "not due_for_renewal? while the certificate has more than 30 days left" do
    install_certificate expiring_in: 60.days

    assert_not Relay::Certificate.instance.due_for_renewal?
  end

  test "due_for_renewal? once the certificate has less than 30 days left" do
    install_certificate expiring_in: 10.days

    assert Relay::Certificate.instance.due_for_renewal?
  end

  test "renew_if_due enqueues a renewal when due and the install manages its own certificate" do
    acme_managed!

    assert_enqueued_with job: Relay::Certificate::RenewalJob do
      Relay::Certificate.renew_if_due
    end
  end

  test "renew_if_due does nothing when the certificate isn't due" do
    acme_managed!
    install_certificate expiring_in: 60.days

    assert_no_enqueued_jobs only: Relay::Certificate::RenewalJob do
      Relay::Certificate.renew_if_due
    end
  end

  test "renew_if_due does nothing when the install doesn't manage its own certificate" do
    assert_no_enqueued_jobs only: Relay::Certificate::RenewalJob do
      Relay::Certificate.renew_if_due
    end
  end

  test "renew answers the challenge records itself, orders the certificate and stores the key and chain as one combined pem" do
    acme_managed!
    chain_pem = stub_acme_order(challenge_status: "valid")

    certificate = Relay::Certificate.instance
    certificate.renew

    assert certificate.pem.end_with?(chain_pem)
    assert_instance_of OpenSSL::PKey::RSA, OpenSSL::PKey.read(certificate.pem)
    assert certificate.acme_account_key.present?
    assert_nil certificate.renewal_error
    assert_nil certificate.reload.acme_challenge_records
  end

  test "renew publishes every pending challenge record, lowercase and without the root label, before asking for validation" do
    acme_managed!(hostname: "MX.Example")
    stub_acme_order identifiers: [ "MX.Example", "smtp.example" ], challenge_status: "valid"

    published = nil
    Relay::Certificate.any_instance.stubs(:await_challenge_record).with { published ||= Relay::Certificate.instance.acme_challenge_records.dup }

    with_env(SUBMISSION_HOSTNAME: "smtp.example") do
      Relay::Certificate.instance.renew
    end

    assert_equal({ "_acme-challenge.mx.example" => "content-MX.Example", "_acme-challenge.smtp.example" => "content-smtp.example" }, published)
    assert_equal "content-MX.Example", Relay::Certificate.new(acme_challenge_records: published).acme_challenge_record_for("_acme-challenge.MX.Example.")
  end

  test "renew names the delegation to publish, without asking Let's Encrypt, when the challenge record never reaches public DNS" do
    acme_managed!
    stub_acme_order challenge_status: "pending", lookups: [ [ "something-else" ] ], validation_requested: false

    certificate = Relay::Certificate.instance
    error = assert_raises(RuntimeError) { certificate.renew }

    assert_equal '_acme-challenge.relay.example does not reach this relay: publish "_acme-challenge.relay.example. NS relay.example." and open port 53', error.message
    certificate.reload
    assert_match(/open port 53/, certificate.renewal_error)
    assert_nil certificate.acme_challenge_records
  end

  test "renew reads a resolver failure as the record not reaching it, since an undelegated name answers SERVFAIL" do
    acme_managed!
    stub_acme_order challenge_status: "pending", validation_requested: false,
      lookups: [ DnsResolver::TransientError.new("server failure resolving TXT _acme-challenge.relay.example") ]

    error = assert_raises(RuntimeError) { Relay::Certificate.instance.renew }

    assert_match(/does not reach this relay/, error.message)
  end

  test "renew records the failure, withdraws the challenge records and keeps the existing certificate when the challenge fails" do
    acme_managed!
    existing_pem = install_certificate(expiring_in: 10.days)
    stub_acme_order challenge_status: "invalid", challenge_error: { "detail" => "DNS problem" }

    certificate = Relay::Certificate.instance
    error = assert_raises(RuntimeError) { certificate.renew }

    assert_match(/DNS problem/, error.message)
    certificate.reload
    assert_equal existing_pem, certificate.pem
    assert_match(/DNS problem/, certificate.renewal_error)
    assert_nil certificate.acme_challenge_records
  end

  test "renew orders one certificate covering every tls_hostname, validating each authorization in turn" do
    acme_managed!(hostname: "mx.example")
    chain_pem = stub_acme_order(identifiers: [ "mx.example", "smtp.example" ], challenge_status: "valid")

    certificate = Relay::Certificate.instance
    with_env(SUBMISSION_HOSTNAME: "smtp.example") do
      certificate.renew
    end

    assert certificate.pem.end_with?(chain_pem)
  end

  test "renew skips an authorization that is already valid and collects the certificate without publishing a challenge record" do
    acme_managed!
    DnsResolver.expects(:txt).never

    chain_pem = build_certificate(cn: "relay.example", expiring_in: 90.days).to_pem
    order = stub(authorizations: [ stub(status: "valid", dns: nil, domain: "relay.example") ], status: "valid", certificate: chain_pem)
    order.expects(:finalize)

    client = mock
    client.expects(:new_account).with(contact: nil, terms_of_service_agreed: true)
    client.expects(:new_order).with(identifiers: [ "relay.example" ]).returns(order)
    Acme::Client.stubs(:new).returns(client)

    certificate = Relay::Certificate.instance
    certificate.renew

    assert certificate.pem.end_with?(chain_pem)
    assert_nil certificate.renewal_error
  end

  test "renew keeps the existing certificate when the issued chain doesn't validate" do
    acme_managed!
    existing_pem = install_certificate(expiring_in: 10.days)
    stub_acme_order(challenge_status: "valid", chain_pem: "-----BEGIN CERTIFICATE-----\ngarbage\n-----END CERTIFICATE-----\n")

    certificate = Relay::Certificate.instance
    assert_raises(ActiveRecord::RecordInvalid) { certificate.renew }

    certificate.reload
    assert_equal existing_pem, certificate.pem
    assert_match(/RecordInvalid/, certificate.renewal_error)
  end

  private
    def acme_managed!(hostname: "relay.example")
      stub_env RELAY_HOSTNAME: hostname
      Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))
    end

    def install_certificate(expiring_in:)
      pem = certificate_pem(cn: "relay.example", expiring_in: expiring_in)
      Relay::Certificate.instance.update!(pem: pem)
      pem
    end

    # Every challenge name answers with its own content unless `lookups` scripts the answers in turn.
    def stub_acme_order(challenge_status:, identifiers: [ "relay.example" ], challenge_error: nil, chain_pem: nil, lookups: nil, validation_requested: true)
      authorizations = identifiers.map do |identifier|
        challenge = stub(record_name: "_acme-challenge", record_content: "content-#{identifier}", status: challenge_status, error: challenge_error)
        challenge.expects(:request_validation).times(validation_requested ? 1 : 0)
        stub_challenge_lookup identifier, lookups || [ [ "content-#{identifier}" ] ]
        stub(status: "pending", dns: challenge, domain: identifier)
      end
      order = stub(authorizations: authorizations)

      client = mock
      client.expects(:new_account).with(contact: nil, terms_of_service_agreed: true)
      client.expects(:new_order).with(identifiers: identifiers).returns(order)
      Acme::Client.stubs(:new).returns(client)

      if challenge_status == "valid"
        chain_pem ||= build_certificate(cn: "relay.example", expiring_in: 90.days).to_pem
        order.expects(:finalize)
        order.stubs(status: "valid", certificate: chain_pem)
        chain_pem
      end
    end

    def stub_challenge_lookup(identifier, answers)
      expectation = DnsResolver.stubs(:txt).with("_acme-challenge.#{identifier.downcase}")
      answers.each { |answer| expectation = (answer.is_a?(Exception) ? expectation.raises(answer) : expectation.returns(answer)).then }
    end
end
