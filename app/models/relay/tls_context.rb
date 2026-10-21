require "openssl"

class Relay::TlsContext
  TLS_CIPHERS = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:" \
    "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:" \
    "ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:" \
    "DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384"

  SELF_SIGNED_CN = "postrider.invalid"

  class << self
    def self_signed
      key = OpenSSL::PKey::RSA.new(2048)

      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = OpenSSL::BN.rand(64)
      cert.subject = cert.issuer = OpenSSL::X509::Name.new([ [ "CN", SELF_SIGNED_CN ] ])
      cert.public_key = key
      cert.not_before = Time.now
      cert.not_after = 30.days.from_now
      cert.sign(key, OpenSSL::Digest.new("SHA256"))

      new(cert.to_pem, key.to_pem)
    end
  end

  attr_reader :ssl_context

  def initialize(cert_pem, key_pem)
    @ssl_context = OpenSSL::SSL::SSLContext.new
    @ssl_context.ciphers = TLS_CIPHERS
    @ssl_context.min_version = OpenSSL::SSL::TLS1_2_VERSION

    certs = certificate_chain(cert_pem)
    @ssl_context.cert = certs.first
    @ssl_context.extra_chain_cert = certs[1..]
    @ssl_context.key = OpenSSL::PKey.read(key_pem)
  end

  def start(io)
    ssl = OpenSSL::SSL::SSLSocket.new(io, ssl_context)
    ssl.sync_close = true
    ssl.accept
    ssl
  end

  private
    def certificate_chain(pem)
      pem.scan(/-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----/m).map do |cert_pem|
        OpenSSL::X509::Certificate.new(cert_pem)
      end
    end
end
