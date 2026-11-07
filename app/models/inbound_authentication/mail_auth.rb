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
    verdicts_of(authenticate)
  rescue StandardError => error
    Rails.error.report(error, severity: :warning)
    verdicts_of(undetermined)
  end

  # Nil when a retry could still vouch for the sender, no slot was free, or authentication crashed,
  # so the sender should try again.
  def settled_verdicts(within:, slots: nil)
    if slots.nil? || slots.claim
      begin
        if (result = authenticate_within(within)) && !unsettled?(result)
          verdicts_of(result)
        end
      ensure
        slots&.release
      end
    end
  end

  private
    def verdicts_of(result)
      {
        spf: result.spf&.status, dkim: result.dkim&.status,
        dmarc: result.dmarc&.status, dmarc_policy: result.dmarc&.policy,
        arc: result.arc&.status, arc_sealer: result.arc&.newest&.seal&.domain,
        iprev: result.iprev&.status, remote_host: result.iprev&.name,
        from_aligned: from_aligned?(result), authentication_results: result.authentication_results
      }
    end

    # Every lookup ends by the deadline, so authentication does too.
    def authenticate_within(seconds)
      authenticate(resolver: self.class.resolver.with_deadline(Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds))
    rescue StandardError => error
      Rails.error.report(error, severity: :warning)
      nil
    end

    def authenticate(resolver: self.class.resolver)
      # `mta:` is the authserv-id every seal we later write is stamped with.
      ::MailAuth.authenticate(@data, ip: @ip, helo: @helo, mail_from: @mail_from, mta: Relay.hostname, resolver:)
    end

    # Only while nothing vouches for the From and a retry could change that: SPF or a DKIM signature
    # aligned with the From failed for now. A DMARC pass needs one of those, and a reverse name decides nothing.
    def unsettled?(result)
      !authenticated?(result) &&
        (temporary?(result.spf) && spf_aligned?(result.spf) || result.dkim.signatures.any? { temporary?(it) && it.aligned })
    end

    def authenticated?(result)
      result.dmarc&.status == ::MailAuth::Status::PASS || from_aligned?(result)
    end

    def temporary?(check)
      check&.status == ::MailAuth::Status::TEMPERROR
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
      result.spf&.status == ::MailAuth::Status::PASS && spf_aligned?(result.spf)
    end

    def spf_aligned?(spf)
      from_domain = ::MailAuth::Message.new(@data).header_from_domain
      from_domain.present? && spf.domain.present? && ::MailAuth::Dmarc::Alignment.aligned?(from_domain, spf.domain, strict: false)
    end
end
