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
    result = authenticate || undetermined

    {
      spf: result.spf&.status, dkim: result.dkim&.status,
      dmarc: result.dmarc&.status, dmarc_policy: result.dmarc&.policy,
      arc: result.arc&.status, arc_sealer: result.arc&.newest&.seal&.domain,
      iprev: result.iprev&.status, remote_host: result.iprev&.name,
      from_aligned: from_aligned?(result), authentication_results: result.authentication_results
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

    # A check that could not finish still states its result, so ours is the first a reader finds.
    def undetermined
      spf = ::MailAuth::SpfResult.new(status: ::MailAuth::Status::TEMPERROR)
      dkim = ::MailAuth::DkimResult.new(signatures: [ ::MailAuth::Signature.new(status: ::MailAuth::Status::TEMPERROR) ])
      dmarc = ::MailAuth::DmarcResult.new(status: ::MailAuth::Status::TEMPERROR)
      iprev = ::MailAuth::IprevResult.new(status: ::MailAuth::Status::TEMPERROR)

      ::MailAuth::Result.new(spf:, dkim:, dmarc:, iprev:,
        authentication_results: ::MailAuth::AuthenticationResults.new(spf:, dkim:, dmarc:, iprev:, mta: Relay.hostname).to_s)
    end

    # From vouched by aligned DKIM/SPF even without a published DMARC policy.
    def from_aligned?(result)
      aligned_dkim?(result) || aligned_spf?(result)
    end

    def aligned_dkim?(result)
      result.dkim.signatures.any? { |signature| signature.status == "pass" && signature.aligned }
    end

    def aligned_spf?(result)
      if result.spf&.status == "pass" && result.spf.domain.present?
        from_domain = ::MailAuth::Message.new(@data).header_from_domain
        from_domain.present? && ::MailAuth::Dmarc::Alignment.aligned?(from_domain, result.spf.domain, strict: false)
      else
        false
      end
    end
end
