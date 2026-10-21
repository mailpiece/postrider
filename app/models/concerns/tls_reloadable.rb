# MailSmtp::Server reads #tls on each STARTTLS; assigning a new context hot-swaps
# without restart. Local envs may self-sign; elsewhere Missing holds the listener until ACME.
module TlsReloadable
  def reload_tls
    self.tls = current_tls
  end

  private
    def current_tls
      if pem = Relay::Certificate.instance.pem.presence
        Relay::TlsContext.new(pem, pem)
      elsif Rails.env.local?
        Relay::TlsContext.self_signed
      else
        raise Relay::Certificate::Missing, "No TLS certificate for #{Relay.hostname.inspect} yet. It is issued automatically via ACME; check Adminland"
      end
    end
end
