require "mailauth"

class InboundAuthentication::MailAuth
  class << self
    # Shared: MailResolver multiplexes only when callers reuse one Resolver.
    def resolver
      @resolver ||= MailResolver::Resolver.new
    end
  end

  def initialize(data, ip: nil, helo: nil, mail_from: nil)
    @data = data
    @ip = ip
    @helo = helo
    @mail_from = mail_from
  end

  def verdicts
    result = authenticate

    {
      spf: result&.spf&.status, dkim: result&.dkim&.status,
      dmarc: result&.dmarc&.status, dmarc_policy: result&.dmarc&.policy,
      arc: result&.arc&.status, arc_sealer: result&.arc&.newest&.seal&.domain,
      from_aligned: from_aligned?(result), authentication_results: result&.authentication_results
    }
  end

  private
    def authenticate
      # `mta:` is the authserv-id every seal we later write is stamped with.
      ::MailAuth.authenticate(@data, ip: @ip, helo: @helo, mail_from: @mail_from, mta: Relay.hostname,
        resolver: self.class.resolver)
    rescue StandardError => error
      Rails.error.report(error, severity: :warning)
      nil
    end

    # From vouched by aligned DKIM/SPF even without a published DMARC policy.
    def from_aligned?(result)
      if result.nil?
        false
      else
        aligned_dkim?(result) || aligned_spf?(result)
      end
    end

    def aligned_dkim?(result)
      result.dkim.signatures.any? { |signature| signature.status == "pass" && signature.aligned }
    end

    def aligned_spf?(result)
      from_domain = ::MailAuth::Message.new(@data).header_from_domain

      result.spf&.status == "pass" && from_domain.present? && result.spf.domain.present? &&
        ::MailAuth::Dmarc::Alignment.aligned?(from_domain, result.spf.domain, strict: false)
    end
end
