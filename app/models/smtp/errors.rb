module Smtp
  # Postrider's own refusals; the rest come from MailGate::Errors and MailSmtp.
  module Errors
    class DomainNotVerified < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    class SendingDisabled < MailSmtp::Error
      status 550, "Requested action not taken: mailbox unavailable", enhanced: "5.7.1"
    end

    # The sender's DNS failed for now, or didn't answer in time, so the sender is asked to try again.
    class AuthenticationUnsettled < MailSmtp::Error
      status 451, "Try again later", enhanced: "4.4.3"
    end
  end
end
