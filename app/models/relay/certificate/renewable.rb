module Relay::Certificate::Renewable
  extend ActiveSupport::Concern

  RENEWAL_THRESHOLD = 30.days

  included do
    encrypts :acme_account_key
  end

  class_methods do
    def renew_if_due
      instance.renew_later if Relay.acme? && instance.due_for_renewal?
    end
  end

  def due_for_renewal?
    expires_at.nil? || expires_at < RENEWAL_THRESHOLD.from_now
  end

  def renew_later
    Relay::Certificate::RenewalJob.perform_later
  end

  def renew
    order = acme_client.new_order(identifiers: Relay.tls_hostnames)
    pass_dns_challenges(order)
    collect_certificate(order)
  rescue StandardError => error
    record_failure(error)
    raise
  end

  private
    def acme_client
      Acme::Client.new(private_key: acme_account_private_key, directory: Relay.acme_directory).tap do |client|
        client.new_account(contact: acme_account_contact, terms_of_service_agreed: true)
      end
    end

    def acme_account_private_key
      if acme_account_key.blank?
        update!(acme_account_key: OpenSSL::PKey::RSA.new(2048).to_pem)
      end

      OpenSSL::PKey::RSA.new(acme_account_key)
    end

    def acme_account_contact
      "mailto:#{Relay.acme_contact}" if Relay.acme_contact
    end

    def pass_dns_challenges(order)
      authorizations = order.authorizations.reject { |authorization| authorization.status == "valid" }

      if authorizations.any?
        update! acme_challenge_records: authorizations.to_h { |authorization| [ challenge_name(authorization), authorization.dns.record_content ] }
        authorizations.each { |authorization| validate_dns_challenge(authorization) }
      end
    ensure
      update! acme_challenge_records: nil
    end

    def challenge_name(authorization)
      "#{authorization.dns.record_name}.#{authorization.domain}".downcase.chomp(".")
    end

    def validate_dns_challenge(authorization)
      challenge = authorization.dns
      await_challenge_record challenge_name(authorization), challenge.record_content

      challenge.request_validation
      poll_while challenge, statuses: %w[ pending processing ]

      unless challenge.status == "valid"
        raise "ACME DNS challenge for #{authorization.domain} ended #{challenge.status.inspect}: #{challenge.error || "timed out"}"
      end
    end

    # Asking Let's Encrypt before the record reaches us would spend a validation against its rate limits.
    def await_challenge_record(name, content)
      unless challenge_record_visible?(name, content)
        raise "#{name} does not reach this relay: publish \"#{name}. NS #{Relay.hostname}.\" and open port 53"
      end
    end

    def challenge_record_visible?(name, content)
      DnsResolver.txt(name).include?(content)
    rescue DnsResolver::TransientError
      false
    end

    def collect_certificate(order)
      certificate_key = OpenSSL::PKey::RSA.new(2048)
      order.finalize(csr: Acme::Client::CertificateRequest.new(private_key: certificate_key, common_name: Relay.hostname, names: Relay.tls_hostnames))
      poll_while order, statuses: %w[ processing ]

      update! pem: certificate_key.to_pem + order.certificate, renewal_error: nil
    end

    def poll_while(resource, statuses:)
      30.times do
        break unless resource.status.in?(statuses)
        sleep 2
        resource.reload
      end
    end

    def record_failure(error)
      restore_attributes
      update!(renewal_error: "#{error.class}: #{error.message}")
    end
end
