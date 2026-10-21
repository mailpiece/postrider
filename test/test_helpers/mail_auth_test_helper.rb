# Stub at ::MailAuth.authenticate: the gem exposes no injector, and production calls this seam.
module MailAuthTestHelper
  def stub_mailauth(spf: "none", dkim: "none", dmarc: "none", dmarc_policy: nil, arc: "none", arc_sealer: nil)
    ::MailAuth.stubs(:authenticate).returns(
      ::MailAuth::Result.new(
        spf: ::MailAuth::SpfResult.new(status: spf, domain: nil),
        dkim: ::MailAuth::DkimResult.new(signatures: [ ::MailAuth::Signature.new(status: dkim, domain: nil) ]),
        dmarc: ::MailAuth::DmarcResult.new(status: dmarc, policy: dmarc_policy),
        arc: arc_result(arc, arc_sealer),
        authentication_results: "test; spf=#{spf}; dkim=#{dkim}; dmarc=#{dmarc}; arc=#{arc}"
      )
    )
  end

  private
    def arc_result(status, sealer)
      sets = if sealer
        [ ::MailAuth::ArcSet.new(instance: 1, seal: ::MailAuth::ArcSeal.new(status: status, domain: sealer)) ]
      else
        []
      end

      ::MailAuth::ArcResult.new(status: status, sets: sets)
    end
end
