module ErrorReporting
  def log(_session, severity, _msg, err: nil)
    super

    report_error(err) if err && reportable?(severity, err)
  end

  private
    def reportable?(severity, err)
      if err.is_a?(MailSmtp::Error) || shutdown? || remote_fault?(err)
        false
      else
        severity == Logger::ERROR || severity == Logger::FATAL
      end
    end

    def remote_fault?(err)
      case err
      when OpenSSL::SSL::SSLError
        true
      when Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT, EOFError
        true
      else
        false
      end
    end

    def report_error(err)
      Rails.error.report(err, handled: false, source: "smtp")
    end
end
