require "test_helper"

class Relay::CertificateTest < ActiveSupport::TestCase
  include CertificateTestHelper

  test "allows a blank pem — the row holds ACME state before the first certificate is issued" do
    assert Relay::Certificate.new(pem: "").valid?
  end

  test "rejects content that doesn't parse as a certificate and key" do
    certificate = Relay::Certificate.new(pem: "not a certificate")

    assert_not certificate.valid?
    assert_match(/doesn't look like a valid certificate/, certificate.errors[:pem].first)
  end

  test "accepts a matching combined cert and key and reports its expiry" do
    cert = build_certificate
    certificate = Relay::Certificate.instance
    certificate.pem = test_rsa_key.to_pem + cert.to_pem

    assert certificate.save
    assert_equal cert.not_after.to_i, certificate.expires_at.to_i
  end

  test "rejects a garbage replacement of an already-valid certificate, without touching the stored one" do
    valid_pem = certificate_pem
    certificate = Relay::Certificate.instance
    certificate.update!(pem: valid_pem)

    assert_not certificate.update(pem: "garbage not a cert")
    assert_match(/doesn't look like a valid certificate/, certificate.errors[:pem].first)
    assert_equal valid_pem, certificate.reload.pem
  end

  test "self_signed? flags a certificate that issued itself" do
    assert Relay::Certificate.new(pem: certificate_pem).self_signed?
  end

  test "self_signed? passes over a certificate issued by someone else" do
    assert_not Relay::Certificate.new(pem: certificate_pem(issuer_cn: "ca.example")).self_signed?
  end

  test "expiring_soon? once the certificate is inside the warning window" do
    assert Relay::Certificate.new(pem: certificate_pem(expiring_in: 7.days)).expiring_soon?
  end

  test "expiring_soon? passes over a certificate with plenty of life left" do
    assert_not Relay::Certificate.new(pem: certificate_pem(expiring_in: 90.days)).expiring_soon?
  end

  test "instance finds the existing row instead of creating a second one" do
    existing = Relay::Certificate.new(pem: "placeholder")
    existing.save!(validate: false)

    assert_no_difference -> { Relay::Certificate.count } do
      assert_equal existing, Relay::Certificate.instance
    end
  end
end
