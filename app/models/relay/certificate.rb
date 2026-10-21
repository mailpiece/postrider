class Relay::Certificate < ApplicationRecord
  include Renewable

  class Missing < StandardError; end

  self.table_name = "relay_certificates"

  encrypts :pem

  EXPIRY_WARNING_WINDOW = 14.days

  validate :pem_parses, if: -> { pem.present? }

  def self.instance
    first_or_initialize
  end

  def expires_at
    certificate&.not_after
  end

  def expiring_soon?
    expires_at.present? && expires_at < EXPIRY_WARNING_WINDOW.from_now
  end

  def self_signed?
    certificate.present? && certificate.issuer == certificate.subject
  end

  # The TXT content the ACME DNS listener answers for a challenge name, while a
  # renewal has one open. Names are stored lowercase without the trailing dot.
  def acme_challenge_record_for(name)
    (acme_challenge_records || {})[name.to_s.downcase.chomp(".")]
  end

  private
    def certificate
      tls_context&.ssl_context&.cert
    end

    def pem_parses
      tls_context
    rescue OpenSSL::X509::CertificateError, OpenSSL::PKey::PKeyError, ArgumentError => error
      errors.add(:pem, "doesn't look like a valid certificate and key: #{error.message}")
    end

    def tls_context
      return unless pem.present?

      if @tls_context_pem != pem
        @tls_context_pem = pem
        @tls_context = Relay::TlsContext.new(pem, pem)
      end

      @tls_context
    end
end
