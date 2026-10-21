module CertificateTestHelper
  def self.test_key
    @test_key ||= OpenSSL::PKey::RSA.new(2048)
  end

  private
    def test_rsa_key
      CertificateTestHelper.test_key
    end

    def build_certificate(key: test_rsa_key, cn: "test.example", issuer_cn: cn, expiring_in: 1.hour)
      certificate = OpenSSL::X509::Certificate.new
      certificate.version = 2
      certificate.serial = 1
      certificate.subject = OpenSSL::X509::Name.new([ [ "CN", cn ] ])
      certificate.issuer = OpenSSL::X509::Name.new([ [ "CN", issuer_cn ] ])
      certificate.public_key = key
      certificate.not_before = Time.now
      certificate.not_after = expiring_in.from_now
      certificate.sign(key, OpenSSL::Digest.new("SHA256"))
      certificate
    end

    def certificate_pem(**options)
      key = test_rsa_key
      key.to_pem + build_certificate(key: key, **options).to_pem
    end
end
