# MailSmtp::Server reads #tls on each STARTTLS; assigning a new context hot-swaps
# without restart.
module TlsReloadable
  def reload_tls
    self.tls = current_tls
  end

  private
    def current_tls
      Relay::TlsContext.current
    end
end
