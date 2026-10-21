require "test_helper"

class Relay::TlsContextTest < ActiveSupport::TestCase
  include CertificateTestHelper

  test "loads an RSA certificate and key from separate pem strings" do
    cert = build_certificate

    context = Relay::TlsContext.new(cert.to_pem, test_rsa_key.to_pem)

    assert_equal cert.to_der, context.ssl_context.cert.to_der
    assert context.ssl_context.cert.check_private_key(context.ssl_context.key)
  end

  test "loads an ECDSA certificate and key, not just RSA" do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = build_certificate(key: key)

    context = Relay::TlsContext.new(cert.to_pem, key.to_pem)

    assert_equal cert.to_der, context.ssl_context.cert.to_der
    assert context.ssl_context.cert.check_private_key(context.ssl_context.key)
  end

  test "loads cert and key from a single combined pem — kamal-proxy's autocert layout (key first, then cert)" do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = build_certificate(key: key)
    combined = key.to_pem + cert.to_pem

    context = Relay::TlsContext.new(combined, combined)

    assert_equal cert.to_der, context.ssl_context.cert.to_der
    assert context.ssl_context.cert.check_private_key(context.ssl_context.key)
  end

  test "parses a full certificate chain, not just the leaf" do
    leaf = build_certificate(cn: "leaf.example")
    intermediate = build_certificate(cn: "intermediate.example")

    context = Relay::TlsContext.new(leaf.to_pem + intermediate.to_pem, test_rsa_key.to_pem)

    assert_equal leaf.to_der, context.ssl_context.cert.to_der
    assert_equal [ intermediate.to_der ], context.ssl_context.extra_chain_cert.map(&:to_der)
  end

  test "completes a TLS 1.2 handshake with an ECDSA certificate — needs the ECDSA cipher suites in TLS_CIPHERS" do
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = build_certificate(key: key)
    context = Relay::TlsContext.new(cert.to_pem, key.to_pem)

    assert_equal cert.to_der, handshake_client(context, max_version: OpenSSL::SSL::TLS1_2_VERSION).peer_cert.to_der
  end

  test "completes a TLS 1.3 handshake — min_version is a floor, not an exact pin" do
    cert = build_certificate
    context = Relay::TlsContext.new(cert.to_pem, test_rsa_key.to_pem)

    client = handshake_client(context, min_version: OpenSSL::SSL::TLS1_3_VERSION)
    assert_equal "TLSv1.3", client.ssl_version
  end

  private
    def handshake_client(context, min_version: nil, max_version: nil)
      server_io, client_io = UNIXSocket.pair
      server = Thread.new { context.start(server_io) }

      client_context = OpenSSL::SSL::SSLContext.new
      client_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      client_context.min_version = min_version if min_version
      client_context.max_version = max_version if max_version

      client = OpenSSL::SSL::SSLSocket.new(client_io, client_context)
      client.connect
      server.value
      client
    end
end
