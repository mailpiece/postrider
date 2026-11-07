module Relay::Backend
  def tls
    Relay::TlsContext.current
  end

  def report_error(error)
    Rails.error.report(error, handled: false, source: "smtp")
  end

  private
    def wrap(&)
      Rails.application.executor.wrap(&)
    end
end
