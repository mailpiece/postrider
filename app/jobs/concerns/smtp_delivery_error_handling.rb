module SmtpDeliveryErrorHandling
  extend ActiveSupport::Concern

  included do
    retry_on Net::OpenTimeout, Net::ReadTimeout, Socket::ResolutionError, wait: :polynomially_longer

    # 4xx temporary errors (e.g. 452 insufficient storage).
    retry_on Net::SMTPServerBusy, wait: :polynomially_longer

    rescue_from Net::SMTPSyntaxError do |error|
      case error.message
      when /\A501 5\.1\.3/
        Rails.error.report(error, handled: true, severity: :info)
      else
        raise
      end
    end

    # Soft-dismiss known permanent recipient/size failures; re-raise the rest.
    rescue_from Net::SMTPFatalError do |error|
      case error.message
      when /\A550 5\.1\.1/, /\A552 5\.6\.0/, /\A555 5\.5\.4/
        Rails.error.report(error, handled: true, severity: :info)
      else
        raise
      end
    end
  end
end
